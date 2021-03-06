require 'docker'

module Grader
  class Worker
    DOCKER_IMAGE_NAME     = 'wmucs/oc'
    CODE_FILE_PLACEHOLDER = '!code_file!'
    STUDENT_HOME_DIR      = '/home/student'

    @@name
    @@container

    # Call up docker to create a new container
    # for us to work with.
    def initialize
      chars  = ('a'..'z').to_a
      @@name = (0..9).map { chars[rand 26] }.join

      Docker.options[:read_timeout] = Rails.configuration.grader['timeout']

      @@container = Docker::Container.create('Cmd' => ['bash'], 'Image' => DOCKER_IMAGE_NAME, 'Tty' => true)
      @@container.start
    end

    # Destroy the container
    def close
      @@container.stop
    end

    # Execute a command in the container
    def exec_cmd (cmd)
      begin
        ret = @@container.exec(cmd)

        {success: ret[2] == 0, stdout: ret[0].join, stderr: ret[1].join}
      rescue Docker::Error::TimeoutError
        {success: false, stdout: '', stderr: 'Execution timeout...'}
      end
    end

    # Execute multiple commands
    def exec_cmds (cmds)
      cmds.each do |cmd|
        yield exec_cmd cmd
      end
    end

    # Get a single file from the container
    def get_file (name)
      path = "/tmp/#{@@name}/"

      Dir.mkdir path unless Dir.exists? path

      offset = 0

      save_name = (0..16).map { ('a'..'z').to_a[rand 26] }.join
      save_path = "#{path}#{save_name}"

      begin
        @@container.copy name do |chunk|
          IO.write save_path, chunk.force_encoding('UTF-8'), offset
          offset += chunk.length
        end

        system "tar -xf #{save_path} -C #{path}"

        "#{path}#{name}"
      rescue Docker::Error::ServerError
        false
      end
    end

    # Get files from the container
    def get_files (files, &block)
      path = "/tmp/#{@@name}/"
      
      Dir.mkdir path unless Dir.exists? path

      files.each do |id, name|
        yield id, get_file(name)
      end
    end

    # Run some code! You must supply the code itself,
    # and the command necessary to run it.
    def run_code (code, cmd)
      code_file = "#{@@name}.code"
      run_file  = "#{@@name}.driver"

      code_file_fqn = "/tmp/#{code_file}"
      run_file_fqn  = "/tmp/#{run_file}"

      IO::write code_file_fqn, code
      IO::write run_file_fqn, cmd.gsub(CODE_FILE_PLACEHOLDER, code_file)

      upload_files [code_file_fqn, run_file_fqn]

      exec_cmd ["bash", "#{run_file}"]
    end

    # Move files into the container
    def upload_files (files)
      @@container.archive_in files, '.'
    end
  end
end

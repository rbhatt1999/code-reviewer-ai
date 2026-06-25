require 'open3'

module Runners
  class Base
    Result = Struct.new(:issues_attrs, :stdout, :stderr, :exit_code, :duration_ms, keyword_init: true)

    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    private

    def subprocess_run(cmd, cwd: Dir.pwd)
      t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3(*cmd, chdir: cwd)
      t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      duration_ms = ((t_end - t_start) * 1000).round
      [stdout, stderr, status.exitstatus, duration_ms]
    end
  end
end

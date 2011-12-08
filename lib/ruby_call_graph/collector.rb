require 'ruby_call_graph'

module RubyCallGraph
  class Collector
    attr_accessor :trace_file

    def clear!
      File.unlink(trace_file) rescue nil
      self
    end

    def start!
      @trace_file ||= "/tmp/ruby_call_graph.txt"
      @trace_fh = File.open(trace_file, "a+")
      @line_count ||= 0
      @old_trace_func =
      set_trace_func Proc.new() { | event, file, line, meth, binding, klass |
        # if event == C_CALL == str or event == CALL_str or event == LINE_str or event == RETURN_str
        clrs = caller[2 .. -1]
        @trace_fh.puts "#{event}|#{file}|#{line}|#{meth}|#{klass}|#{klass.class.inspect}|#{clrs && clrs.join('|')}"
        @line_count += 1
        # end
      }
      $stderr.puts "#{self}: logging to #{@trace_file.inspect}"
      self
    end

    def stop!
      set_trace_func @old_trace_func
      @old_trace_func = nil
      $stderr.puts "#{self}: logged #{@line_count.inspect} events to #{@trace_file.inspect}"
      @trace_fh.close if @trace_fh
      @trace_fh = nil
      self
    end

    def capture!
      start!
      yield
    ensure
      stop!
    end
  end
end

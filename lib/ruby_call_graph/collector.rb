require 'ruby_call_graph'

module RubyCallGraph
  class Collector
    attr_accessor :trace_file
    attr_accessor :verbosity

    def initialize opts = nil
      @verbosity = 0
      @opts = opts ||= { }
      opts.each do | k, v |
        s = :"#{k}="
        send(s, v)
      end
    end

    def clear!
      File.unlink(trace_file) rescue nil
      self
    end

    def start!
      @trace_file ||= "/tmp/ruby_call_graph.txt"
      @trace_fh = File.open(trace_file, "a+")
      @line_count ||= 0
      this = self
      @old_trace_func =
      set_trace_func Proc.new() { | event, file, line, meth, binding, klass |
        @trace_fh.write event
        @trace_fh.write SEP
        @trace_fh.write file
        @trace_fh.write SEP
        @trace_fh.write line
        @trace_fh.write SEP
        @trace_fh.write meth
        @trace_fh.write SEP
        @trace_fh.write this.class_name(klass)
        @trace_fh.write SEP
        @trace_fh.write this.class_name(klass.class)
        # @trace_fh.write SEP
        # @trace_fh.write this.class_name(binding.__self.class)
        @trace_fh.write SEP_NEWLINE
        @line_count += 1
      }
      $stderr.puts "#{self}: logging to #{@trace_file.inspect}" if @verbosity >= 1
      self
    end
    def class_name cls
      if cls && (x = cls.name).empty?
        x = cls.inspect
      end
      x
    end
    def stop!
      set_trace_func @old_trace_func
      @old_trace_func = nil
      $stderr.puts "#{self}: logged #{@line_count.inspect} events to #{@trace_file.inspect}" if @verbosity >= 1
      @trace_fh.close if @trace_fh
      @trace_fh = nil
      self
    end

    def capture!
      raise ArgumentError "block not given" unless block_given?
      start!
      yield
    ensure
      stop!
    end
  end
end

=begin
class ::Binding
  SELF = "self".freeze
  def __self
    unless @__self_ok
      @__self_ok = true
      @__self = eval(SELF, self)
    end
    @__self
  end
end
=end


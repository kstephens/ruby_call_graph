require 'ruby_call_graph'
require 'pp'

if ENV['RUBY_CALL_GRAPH_DEBUGGER']
  require 'rubygems'
  gem 'ruby-debug'
  require 'ruby-debug'
  $debugger = true
end

class ::Object
  def to_const_str
    to_s
  end
end

class ::Symbol
  def to_const_str
    @to_const_str ||= to_s.freeze
  end
  alias :-@ :to_const_str
end

module RubyCallGraph
  class Generator
    attr_accessor :args
    attr_accessor :input
    attr_accessor :include, :exclude, :filter

    def initialize
      @verbosity = 0
      @include = [ ]
      @exclude = [ ]
      @exclude.push "^RubyCallGraph::"
    end

    def args
      @args ||= ARGV.dup
    end

    def input
      @input ||= "/tmp/ruby_call_graph-#{$$}.txt"
    end

    def parse_args!
      until args.empty?
        case arg = args.shift
        when '-v'
          @verbosity += 1
        when '-c'
          @clear = true
        when '-i'
          @include.push args.shift
        when '-e'
          @exclude.push args.shift
        when '-ecore'
          @exclude.push *CORE_PATTERNS
        when '--'
          @cmd = args.dup
          args.clear
        else
          @input = arg
        end
      end
      self
    end
    CORE_PATTERNS =
      %w{
      Object Kernel Class Module
      Method UnboundMethod Proc
      Comparable
      NilClass TrueClass FalseClass
      Numeric Integer Fixnum Bignum Float Rational Complex
      String Symbol
      Regexp MatchData
      Enumerable Hash Array Range Set Queue
      Date Time DateTime
      IO
      Thread ThreadGroup Mutex ConditionVariable
      }.map{|x| "^#{x}( |::)"}.freeze

    def run!
      if @cmd
        file = ENV['RUBY_CALL_GRAPH_LOG'] = File.expand_path(input)
        if @clear
          File.unlink(file) rescue nil
        end
        ENV["RUBYLIB"] = "#{ENV['RUBYLIB']}:#{File.expand_path('../..', __FILE__)}"
        @cmd = [ "ruby", "-rruby_call_graph/setup", *@cmd ]
        $stderr.puts "#{$0}: exec #{@cmd.inspect}" if @verbosity >= 1
        exec(*@cmd)
        raise "Cannot exec #{@cmd.inspect}"
      end

      # Mapping of file:line to ClsMeth object.
      obj_to_cls_meth = { }

      # Stand-in for program top-level/main.
      main = ClsMeth.new(:'-MAIN-', :'-MAIN-', :'-MAIN-')
      obj_to_cls_meth[main.name] = main

      # Output: [ sndr stack, rcvr ]
      sndr_rcvrs = [ ]
      sndr_stack = [ ]
      indent = { }
      n_read = 0
      sndr_stacks = { }
      progress = Progress.new(:lines).start! if @verbosity >= 1
      File.open(self.input) do | io |
        until io.eof?
          n_read += 1
          progress.tick! if @verbosity >= 1
          record = io.readline
          record.chomp!
          event, file, line, meth, cls, cls_class, *rest = record.split('|')
          #i = indent[call_level] ||= (-:' ' * (call_level > 0 ? call_level : 0)).freeze
          #$stderr.write i; $stderr.write -:|; $stderr.puts rcvr_file_line

          if ! meth.empty? and cls != FALSE_str
            name = :"#{cls} #{meth}"
            cls_meth = obj_to_cls_meth[name] ||=
              ClsMeth.new(name, cls.to_sym, meth.to_sym)

            file_line = :"#{file}:#{line}"
            if event == C_CALL_str
              rcvr = cls_meth
            else
              rcvr = file_line
            end

            case event
            when CALL_str, LINE_str, RETURN_str
              # Save the class#method for this line number.
              obj_to_cls_meth[file_line] ||= cls_meth
            end

            case event
            when C_CALL_str, CALL_str
              x = [ sndr_stack.reverse, rcvr ]
              sndr_rcvrs << x
            end

            case event
            when CALL_str, C_CALL_str
              sndr_stack.push rcvr
            when RETURN_str, C_RETURN_str
              sndr_stack.pop
            end
          end

          # puts "#{sndr_file_line.inspect} -> #{rcvr_file_line.inspect} #{cls_meth.inspect}"
        end
      end
      n_calls = sndr_rcvrs.size
      progress.complete! if @verbosity >= 1

=begin
      # Uniquify sndrs.
      sndrs = { }
      sndr_rcvrs.each do | x |
        x[0] = sndrs[x[0]] ||= x[0]
      end
=end

      # Identity mapping of ClsMeths.
      obj_to_cls_meth.values.each do | cls_meth |
        obj_to_cls_meth[cls_meth] = cls_meth
      end

      # Prepare filter for Class#method.
      include_proc =
        unless include.empty?
          include_rx = Regexp.new(include.map{|x| "(#{x})"} * '|')
          Proc.new { | x | include_rx.match(x) }
        else
          Proc.new { false }
        end
      exclude_proc =
        unless exclude.empty?
          exclude_rx = Regexp.new(exclude.map{|x| "(#{x})"} * '|')
          Proc.new { | x | exclude_rx.match(x) }
        else
          Proc.new { false }
        end
      self.filter = Proc.new { | x | x = x.to_const_str; include_proc.call(x) || ! exclude_proc.call(x) }

      # Convert each:
      #   [ [ file:line , ...], Class#method rcvr ]
      # to:
      #   [ [ Class#method senders, ... ], Class#method rcvr ]
      # and
      # Find first sender that matches the filter.
      cls_meth_sndr_rcvrs = Hash.new { | h, k | h[k] = { } }
      progress = Progress.new(:calls).start! if @verbosity >= 1
      sndr_rcvrs.each do | x |
        sndrs, rcvr = *x

        # Convert all sender file:line to class#method.
        rcvr = obj_to_cls_meth[rcvr] || rcvr

        # Ignore sndrs without matching rcvr.
        # $stderr.puts rcvr.inspect
        next unless filter.call(rcvr.to_const_str)

        sndrs.map!{ | sndr | obj_to_cls_meth[sndr] || sndr }
        sndrs = [ main ] if sndrs.empty?

        # Find first sender in the stack trace that matches the filter.
        call_type = :direct
        sndr = sndrs.find do | sndr |
          sndr = sndr.to_const_str
          if filter.call(sndr.to_const_str)
            true
          else
            call_type = :indirect
            false
          end
        end

        # Ignore rcvrs without matching sndr.
        next unless sndr

        # Keep track of each sndr -> rcvr as
        # sender[rcvr] = [ count ]
        $stderr.puts "#{sndr} -> #{rcvr}" if @verbosity >= 2
        progress.tick! if @verbosity >= 1
        c = cls_meth_sndr_rcvrs[sndr][rcvr] ||= {
          :sndr => sndr,
          :rcvr => rcvr,
          :all => 0,
          :direct => 0,
          :indirect => 0,
        }
        c[:all] += 1
        c[call_type] += 1
        rcvr.calls!(call_type)
      end
      progress.complete! if @verbosity >= 1
      # pp(cls_meth_sndr_rcvrs)

      # pp file_line_to_cls_meth

      # Convert to { sender Class#method => [ rcvr Class#method, ... ] }
      h = { }
      cls_meth_sndr_rcvrs.each do | sndr, rcvrs |
        h[sndr] = rcvrs.keys
      end

      # Get a list of methods for each class.
      cls_meths = Hash.new { | h, k | h[k] = [ ] }
      (h.keys + h.values).
        flatten.uniq.each do | cls_meth |
        cls_meths[cls_meth.cls] << cls_meth
      end

      if @verbosity >= 1
        $stderr.puts "\n"
        $stderr.puts "Lines read: #{n_read}"
        $stderr.puts "Calls: #{n_calls}"
        $stderr.puts "Class/methods created: #{ClsMeth.count}"
        $stderr.puts "Unique Class#method senders: #{cls_meth_sndr_rcvrs.keys.size}"
      end
      n_methods = 0
      n_interactions = 0

      puts "digraph ruby_call_graph {"
      puts %Q{  label=#{"#{input} - #{Time.now.inspect}".inspect};}
      puts %Q{  labelloc=t; }
      puts "  overlap=false;"
      puts "  splines=true;"

      # Do subgraph for each class,
      # Imbedd methods in each class subgraph.
      cls_meths.each do | cls, meths |
        cls_s = cls.to_const_str.inspect
        puts "  subgraph #{cls_s} {"
        puts "    label=#{cls_s};"
        # puts "    node [ shape=box, style=dotted, label=#{cls_s}, tooltip=#{cls_s} ] #{cls_s};"
        meths.each do | cls_meth |
          n_methods += 1
          cls_meth_s = cls_meth.to_const_str.inspect
          label = "#{cls_meth.cls}\n#{cls_meth.meth}\ncalls:#{cls_meth.calls[:all]},#{cls_meth.calls[:direct]},#{cls_meth.calls[:indirect]}".inspect
          puts %Q{    node [ shape=box, label=#{label}, tooltip=#{cls_meth_s} ] #{cls_meth_s}; }
        end
        puts "  }"
        puts ""
      end

      edge_style = {
        :direct => :solid,
        :indirect => :dashed,
      }
      cls_meth_sndr_rcvrs.keys.sort_by{|k| k.to_const_str}.each do | sndr |
        rcvrs = cls_meth_sndr_rcvrs[sndr]
        rcvrs.keys.sort_by{|k| k.to_const_str}.each do | rcvr |
          $stderr.puts "#{sndr} -> #{rcvr} #{rcvr.calls.inspect}" if @verbosity >= 2
          [ :direct, :indirect ].each do | call_type |
            if (n = rcvr.calls[call_type]) > 0
              n_interactions += 1
              tooltip = "#{sndr} -> #{rcvr} #{call_type}:#{n}".inspect
              puts %Q{  #{sndr.to_const_str.inspect} -> #{rcvr.to_const_str.inspect} [ style=#{edge_style[call_type]}, tooltip=#{tooltip}, labeltooltip=#{tooltip}, label=#{n.inspect} ]; }
            end
          end
        end
      end
      puts "}"

      if @verbosity >= 1
        $stderr.puts "Unique methods: #{n_methods}"
        $stderr.puts "Unique sender/receiver interactions: #{n_interactions}"
      end
    end # run!

  end # class

  class ClsMeth
    @@count = 0
    def self.count; @@count; end
    attr_accessor :cls, :meth, :name
    attr_accessor :calls
    def to_const_str
      @name.to_const_str
    end
    alias :to_s :to_const_str
    def initialize name, cls, meth
      @@count += 1
      @name = name
      @cls  = cls
      @meth = meth
      @calls = { }
      @calls.default = 0
    end
    def calls! call_type
      @calls[:all] += 1
      @calls[call_type] += 1
      self
    end
  end

  class Progress
    attr_accessor :name, :tick, :denomination, :factor
    def initialize name
      @name = name
      @factor = 10
    end
    def start!
      $stderr.write "#{name}:" if name
      @tick = 0
      @denomination = 1
      self
    end
    def tick!
      if (@tick += 1) % @denomination == 0
        $stderr.write " #{@tick}"
        if @tick / @denomination == @denomination
          @denomination *= @factor
        end
        self
      end
    end
    def complete!
      $stderr.puts ": #{@tick} #{name}."
      self
    end
  end

end # module

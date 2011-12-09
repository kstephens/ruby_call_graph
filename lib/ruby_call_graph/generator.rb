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
        when '--'
          @cmd = args.dup
          args.clear
        else
          @input = arg
        end
      end
      self
    end

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

      # Mapping of file:line to class#method
      file_line_to_cls_meth = { }
      cls_method_to_file_line_range = { }
      file_line_sndr_rcvrs = { }

      sndr_rcvrs = [ ]
      indent = { }

      sndr_stack = [ ]
      n_read = 0
      n_processed = 0
      File.open(self.input) do | io |
        until io.eof?
          n_read += 1
          if @verbosity >= 1
            $stderr.write ".#{n_read}" if n_read % 100 == 0
          end
          record = io.readline
          record.chomp!
          event, file, line, meth, cls, cls_class, *clrs = record.split('|')
          #i = indent[call_level] ||= (-:' ' * (call_level > 0 ? call_level : 0)).freeze
          #$stderr.write i; $stderr.write -:|; $stderr.puts rcvr_file_line

          if ! meth.empty? and cls != FALSE_str
            cls_meth  = "#{cls} #{meth}".to_sym
            file_line = "#{file}:#{line}".to_sym
            clrs.map!{|clr| clr.split(':in `').first.to_sym}
            if event == C_CALL_str
              rcvr = cls_meth
            else
              rcvr = file_line
            end

            case event
=begin
            when C_CALL_str
              # Save the class#method for this line number.
              file_line_to_cls_meth[rcvr] = 
                file_line_to_cls_meth[file_line] ||= rcvr
=end
            when CALL_str, LINE_str, RETURN_str
              # Save the class#method for this line number.
              file_line_to_cls_meth[cls_meth] = 
                file_line_to_cls_meth[file_line] ||= cls_meth
            end

            case event
            when C_CALL_str, CALL_str
              x = [ sndr_stack.reverse, rcvr ]
              sndr_rcvrs << x
              if @verbosity >= 1
                $stderr.write "*#{n_processed}" if n_processed % 100 == 0
              end
              n_processed += 1
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

      # Prepare filter for Class#method.
      include_proc =
        unless include.empty?
          include_rx = Regexp.new(include.map{|x| "(#{x})"} * '|')
          Proc.new { | x | include_rx.match(x) }
        else
          Proc.new { true }
        end
      exclude_proc =
        unless exclude.empty?
          exclude_rx = Regexp.new(exclude.map{|x| "(#{x})"} * '|')
          Proc.new { | x | exclude_rx.match(x) }
        else
          Proc.new { false }
        end
      self.filter = Proc.new { | x | x = x.to_const_str; include_proc.call(x) && ! exclude_proc.call(x) }

      # Convert each:
      #   [ [ file:line , ...], Class#method rcvr ]
      # to:
      #   [ [ Class#method senders, ... ], Class#method rcvr ]
      # and
      # Find first sender that matches the filter.
      cls_meth_sndr_rcvrs = { }
      sndr_rcvrs.each do | x |
        sndrs, rcvr = *x
        # Convert all sender file:line to class#method.
        rcvr = file_line_to_cls_meth[rcvr] || rcvr

        # Ignore sndrs without matching rcvr.
        # $stderr.puts rcvr.inspect
        next unless filter.call(rcvr.to_const_str)

        debugger if $debugger && rcvr.to_const_str == 'B bar'
        sndrs.map!{ | sndr | file_line_to_cls_meth[sndr] || sndr }
        debugger if $debugger && sndrs.include?(:'Range each')
        sndrs = [ :'-MAIN-' ] if sndrs.empty?
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
        $stderr.puts "#{sndr} -> #{rcvr}" if @verbosity >= 2
        # Keep track of each sndr -> rcvr as
        # sender[rcvr] = [ count ]
        c = (cls_meth_sndr_rcvrs[sndr] ||= { })[rcvr] ||= { :count => 0, :direct => 0, :indirect => 0 }
        c[:count] += 1
        c[call_type] += 1
      end
      # pp(cls_meth_sndr_rcvrs)

      # pp file_line_to_cls_meth

=begin
      # Convert file:line senders to class#method senders.
      file_line_sndr_rcvrs.each do | sndr, rcvrs |
        sndr_cls_meth = file_line_to_cls_meth[sndr] || :'-MAIN-'
        cls_meth_sndr_rcvrs[sndr_cls_meth] = rcvrs
      end
=end

      # Convert to { sender Class#method => [ rcvr Class#method, ... ] }
      h = { }
      cls_meth_sndr_rcvrs.each do | sndr, rcvrs |
        h[sndr] = rcvrs.keys
      end

      # Get a list of methods for each class.
      cls_meths = { }
      meth_cls = { }
      (h.keys + h.values).
        flatten.uniq.each do | cls_meth |
        cls, meth = *cls_meth.to_const_str.split(' ', 2)
        # $stderr.puts "cls = #{cls.inspect} meth = #{meth.inspect}"
        cls = cls.nil? || cls.empty? ? nil : cls.to_sym
        meth = meth.nil? || meth.empty? ? nil : meth.to_sym
        (cls_meths[cls] ||= [ ]) << [ cls_meth, meth ]
        meth_cls[meth] ||= cls
        meth_cls[cls_meth] ||= cls
      end

      if @verbosity >= 1
        $stderr.puts "\n"
        $stderr.puts "Lines read: #{n_read}"
        $stderr.puts "Lines processed: #{n_processed}"
        $stderr.puts "File/line sites: #{file_line_to_cls_meth.size}"
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
        meths.each do | meth |
          n_methods += 1
          cls_meth, meth = *meth
          cls_meth_s = cls_meth.to_const_str.inspect
          meth_s = meth.to_const_str.inspect
          puts %Q{    node [ shape=box, label=#{(cls.to_const_str + "\n" + meth.to_const_str).inspect}, tooltip=#{cls_meth_s} ] #{cls_meth_s};}
          # puts "    #{cls_s} -> #{cls_meth_s} [ style=dotted, arrowhead=none ];"
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
          data = rcvrs[rcvr]
          $stderr.puts "#{sndr} -> #{rcvr} #{data.inspect}" if @verbosity >= 2
          [ :direct, :indirect ].each do | call_type |
            if data[call_type] > 0
              n_interactions += 1
              tooltip = "#{sndr} -> #{rcvr} (#{call_type})"
              puts %Q{  #{sndr.to_const_str.inspect} -> #{rcvr.to_const_str.inspect} [ style=#{edge_style[call_type]}, ededgetooltip=#{tooltip.inspect}, label=#{data[call_type]} ];}
              # puts "  #{sndr.to_const_str.inspect} -> #{meth_cls[rcvr].to_const_str.inspect} [ style=dotted, arrowhead=open, edgeURL="blank:", edgetooltip="#{tooltip"} ];"
            end
          end
        end
      end
      puts "}"

      if @verbosity >= 1
        $stderr.puts "Unique methods: #{n_methods}"
        $stderr.puts "Unique methods/method interactions: #{n_interactions}"
      end
    end # run!

  end
end

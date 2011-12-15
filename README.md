ruby_call_graph
===============

Generate a GraphVis (http://graphviz.org) Dot graph of method-to-method calls and counts.

Generating Call Logs
--------------------

* Logging entire program:

    rm -f ex01.log     # log file is appended.
    bin/ruby_call_graph ex01.log -- example/ex01.rb

* Logging portion of program:

    require 'ruby_call_graph/collector'
    RubyCallGraph::Collector.new(:trace_file => '/tmp/mytrace.txt').clear!.capture! do
      do_stuff
    end

Processing Call Logs into Graphs
--------------------------------
 
    bin/ruby_call_graph ex01.log | dot -Tsvg -o ex01.svg

* Filtering:

    bin/ruby_call_graph -e 'Range each' ex01.log | dot -Tsvg -o ex01.svg

* Filtering all core classes:

    bin/ruby_call_graph -ecore ex01.log | dot -Tsvg -o ex01.svg

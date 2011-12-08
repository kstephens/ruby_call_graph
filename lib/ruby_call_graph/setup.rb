require 'ruby_call_graph/collector'

begin
  collector = RubyCallGraph::Collector.new
  if collector.trace_file = ENV['RUBY_CALL_GRAPH_LOG']
    at_exit { collector.stop! }
    collector.start!
  end
end

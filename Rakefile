
task :default => :examples

GARBAGE = [ ]
EXAMPLES_SVG = [ ]

Dir['example/ex*.rb'].each do | ex_rb |
  ex_log = "#{ex_rb}.log"
  file ex_log => ex_rb do
    sh "rm -f #{ex_log}"
    sh "bin/ruby_call_graph #{ex_log} -- #{ex_rb}"
  end
  [ [ "", "" ], 
    [ "-exclude-core", "-ecore" ], 
    [ '-exclude-B-bar', "-e 'B bar'" ]
  ].each do | (name, opts) |
    ex_dot = "#{ex_log}#{name}.dot"
    ex_svg = "#{ex_dot}.svg"
    file ex_svg => ex_log do
      sh "bin/ruby_call_graph #{opts} #{ex_log} > #{ex_dot}"
      sh "dot -Tsvg #{ex_dot} -o #{ex_svg}"
    end
    GARBAGE.push(ex_log, ex_dot, ex_svg)
    EXAMPLES_SVG << ex_svg
  end
end

task :examples => EXAMPLES_SVG

task :clean do
  sh "rm -f #{GARBAGE * " "}"
end


#!/usr/bin/env ruby

class A
  attr_accessor :b
  def foo
    (0..10).each do | x |
      b.bar(x)
    end
  end
end

class B
  def bar x
    B.baz x
  end
  def self.baz x
    puts x * 2
  end
end

a = A.new
b = B.new
a.b = b
a.foo

exit(0)

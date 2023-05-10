# frozen_string_literal: true

require_relative 'utils'

# Base class for all Forth keywords. Each keyword on initialization takes in the line starting after
# the keyword so it can parse it as necessary. Whatever is leftover from parsing is stored in @remainder,
# so the interpreter can continue parsing from where the keyword left off. (I.e @remainder is the line after
# the keyword and any associated arguments) Each keyword has an eval method, which takes the interpreter as
# an argument, and uses the interpreter's methods to preform its operation on the interpreter's stack.
class ForthKeyWord
  attr_reader :remainder

  # also, the wildcard is used to catch any extra arguments that may be passed in
  # for more complex words that inherit from this class (Like ForthString, ForthIf, etc.)
  def initialize(line, *)
    @remainder = line
  end

  private

  # checks if the stack has at least num non-nil values
  def underflow?(interpreter, num = 1)
    if (values = interpreter.stack.last(num).compact).length < num
      interpreter.err "#{STACK_UNDERFLOW} Stack contains #{values.length}/#{num} required value(s): #{values}."
      return true
    end
    false
  end
end

# All math operations inherit from this, because the only
# difference between them is the operator they use.
class ForthMathWord < ForthKeyWord
  def initialize(line, opr, *)
    super(line)
    @opr = opr
  end

  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (v1, v2) = interpreter.stack.pop(2)
    interpreter.stack << begin
      v1.send(@opr, v2)
    rescue ZeroDivisionError
      0
    end
  end
end

# Forth + operation
class ForthAdd < ForthMathWord
  def initialize(line, *)
    super(line, :+)
  end
end

# Forth - operation
class ForthSub < ForthMathWord
  def initialize(line, *)
    super(line, :-)
  end
end

# Forth * operation
class ForthMul < ForthMathWord
  def initialize(line, *)
    super(line, :*)
  end
end

# Forth / operation
class ForthDiv < ForthMathWord
  def initialize(line, *)
    super(line, :/)
  end
end

# Forth MOD operation
class ForthMod < ForthMathWord
  def initialize(line, *)
    super(line, :%)
  end
end

# Forth AND operation
class ForthAnd < ForthMathWord
  def initialize(line, *)
    super(line, :&)
  end
end

# Forth OR operation
class ForthOr < ForthMathWord
  def initialize(line, *)
    super(line, :|)
  end
end

# Forth XOR operation
class ForthXor < ForthMathWord
  def initialize(line, *)
    super(line, :^)
  end
end

# Forth CR operation (print newline)
class ForthCr < ForthKeyWord
  def eval(_)
    puts ''
  end
end

# Forth . operation (Pops and prints top of stack)
class ForthDot < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter)

    print "#{interpreter.stack.pop} "
    interpreter.newline = true
  end
end

# Forth DROP operation. (Pops top of stack)
class ForthDrop < ForthKeyWord
  def eval(interpreter)
    interpreter.stack.pop
  end
end

# Forth DUMP operation. (Prints stack)
class ForthDump < ForthKeyWord
  def eval(interpreter)
    puts '' if interpreter.newline
    interpreter.newline = false
    puts "[#{interpreter.stack.join(', ')}]"
  end
end

# Forth DUP operation. (Duplicates top of stack)
class ForthDup < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter)

    interpreter.stack << interpreter.stack.last
  end
end

# Forth EMIT operation. (Prints ASCII of top of stack)
class ForthEmit < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter)

    print "#{interpreter.stack.pop.to_s[0].codepoints.join(' ')} "
    interpreter.newline = true
  end
end

# Forth = operation
class ForthEqual < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (v1, v2) = interpreter.stack.pop(2)
    interpreter.stack << (v1 == v2 ? -1 : 0)
  end
end

# Forth > operation
class ForthGreater < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (v1, v2) = interpreter.stack.pop(2)
    interpreter.stack << (v1 > v2 ? -1 : 0)
  end
end

# Forth INVERT operation
class ForthInvert < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter)

    interpreter.stack << ~interpreter.stack.pop
  end
end

# Forth < operation
class ForthLesser < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (v1, v2) = interpreter.stack.pop(2)
    interpreter.stack << (v1 < v2 ? -1 : 0)
  end
end

# Forth OVER operation. (Copies the second value on the stack in front of the first)
class ForthOver < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (v1, v2) = interpreter.stack.pop(2)
    interpreter.stack.insert(-1, v1, v2, v1)
  end
end

# Forth ROT operation. (Rotates the order of the top three values on the stack)
class ForthRot < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 3)

    (v1, v2, v3) = interpreter.stack.pop(3)
    interpreter.stack.insert(-1, v2, v3, v1)
  end
end

# Forth SWAP operation. (Swaps the places of the first two stack elements)
class ForthSwap < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (v1, v2) = interpreter.stack.pop(2)
    interpreter.stack.insert(-1, v2, v1)
  end
end

# On eval, pushes the value in the heap at the address on the
# top of the stack to the top of the stack.
class ForthGetVar < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter)

    interpreter.stack << interpreter.heap.get(interpreter.stack.pop)
  end
end

# On eval, sets the address on the top of the stack to the
# value on the second to top of the stack.
class ForthSetVar < ForthKeyWord
  def eval(interpreter)
    return if underflow?(interpreter, 2)

    (val, addr) = interpreter.stack.pop(2)
    interpreter.heap.set(addr, val)
  end
end

# Parent class for Variable and Constant definition objects.
class ForthVarDefine < ForthKeyWord
  def initialize(line, *)
    @name = line.shift&.downcase
    super(line)
  end

  private

  def valid_def(name, interpreter, id)
    if name.nil?
      return interpreter.err "#{SYNTAX} Empty #{id} definition"
    elsif @name.integer?
      return interpreter.err "#{BAD_DEF} #{id.capitalize} names cannot be numbers"
    elsif interpreter.system?(@name)
      return interpreter.err "#{BAD_DEF} '#{@name}' is already defined"
    end

    true
  end
end

# Defines a variable in the heap. On eval, allocate
# free space in the heap and store the address under '@name',
# which was read in as the first value on the line.
class ForthVariable < ForthVarDefine
  def eval(interpreter)
    return unless valid_def(@name, interpreter, 'variable')

    interpreter.heap.create(@name)
  end
end

# Defines a global constant. Sets @name to be the first value
# popped off the stack in the interpeter's constants list.
class ForthConstant < ForthVarDefine
  def eval(interpreter)
    return unless valid_def(@name, interpreter, 'constant')
    return if underflow?(interpreter)

    interpreter.constants[@name.to_sym] = interpreter.stack.pop
  end
end

# On eval, takes the top value of the stack as an address and
# allocates that much free space in the heap.
class ForthAllot < ForthVarDefine
  def eval(interpreter)
    return if underflow?(interpreter)

    interpreter.heap.allot(interpreter.stack.pop)
  end
end

# Doesn't do anything in this implementation.
class ForthCells < ForthKeyWord
  def eval(_) end
end

# Parent class for Forth Words that can span multiple lines.
class ForthMultiLine < ForthKeyWord
  def initialize(line, source, stop_if_empty, end_word: '')
    super(line)
    @source = source
    @good = true
    @stop_if_empty = stop_if_empty
    @remainder = read_until(line, @block = [], end_word) if line
  end

  private

  def read_until(line, block, end_word)
    while (word = line.shift) != end_word
      line = @source.gets.split if line.empty? && !@stop_if_empty
      return [] unless check_good(line)

      block << word if word
    end
    line
  end

  def check_good(line)
    @stop_if_empty && line.empty? ? @good = false : true
  end
end

# Forth String. On eval, prints the line up to the first "
# character. Sets @remainder to the line after the ". If
# there is no ", it raises a warning on eval when stop_if_empty
# is true, otherwise it keeps reading until it finds one.
class ForthString < ForthMultiLine
  def initialize(*args)
    super(*args, end_word: '"')
  end

  def eval(interpreter)
    return interpreter.err "#{SYNTAX} No closing '\"' found" unless @good

    print "#{@block.join(' ')} "
    interpreter.newline = true
  end
end

# Forth Comment. Behaves the same as ForthString, except doesn't print anything.
class ForthComment < ForthMultiLine
  def initialize(*args)
    super(*args, end_word: ')')
  end

  def eval(interpreter)
    return interpreter.err "#{SYNTAX} No closing ')' found" unless @good
  end
end

# Creates a user defined word. Reads in the name of the word,
# then copies the input as-is into @block. On eval, updates the
# interpreter's user_words hash with the new name and block.
class ForthWordDef < ForthMultiLine
  def initialize(line, source, *)
    @name = line.shift&.downcase
    super(line, source, @name.nil? || @name == ';', end_word: ';')
  end

  def eval(interpeter)
    return interpeter.err "#{BAD_DEF} No name given for word definition" if @name.nil? || @name == ';'
    return interpeter.err "#{BAD_DEF} Word names cannot be builtins or variable names"\
    if interpeter.system?(@name) && !interpeter.user_words.key?(@name.to_sym)
    return interpeter.err "#{BAD_DEF} Word names cannot be numbers" if @name.integer?

    interpeter.user_words[@name.to_sym] = @block
  end
end

# Parent class for control operators like IF DO, and BEGIN.
# Shadows it's parent's read_until method, because
# it needs to handle ForthCntrlObjs differently on read.
class ForthControlWord < ForthMultiLine
  private

  def read_until(line, block, end_word)
    loop do
      line = @source.gets.split if line.empty? && !@stop_if_empty
      return [] unless check_good(line)
      break if (word = line.shift) && word.downcase == end_word

      line = add_to_block(block, word, line)
    end
    line
  end

  # adds words into a block of the class. If the word read corresponds to a ForthCntrlWord, creates a
  # new instance immediately and starts reading into it rather than reading just the strings in.
  # This is because control objects can be nested, and if they weren't initialized immediately the
  # outermost object would stop at the first termination word, rather than the outermost (E.g if we
  # had IF IF THEN THEN, the first IF would stop at the first THEN, instead of the second.)
  def add_to_block(block, word, line)
    block << word = ForthControlWord.const_get("Forth#{word.capitalize}").new(line, @source, @stop_if_empty)
    word.remainder
    # if the above fails, it's a normal word.
  rescue NameError
    block << word if word
    line
  end
end

# Holds a forth IF statement. Reads into @true_block until it finds an ELSE or THEN. If
# it finds a THEN, it reads into @false_block until it finds a THEN. On eval, pops
# the top of the stack and if it's 0, evaluates @false_block, otherwise @true_block.
class ForthIf < ForthControlWord
  def initialize(line, source, stop_if_empty)
    super(nil, source, stop_if_empty)
    @true_block = []
    @false_block = []
    @remainder = read_true(line)
  end

  def eval(interpreter)
    # If the IF is not good (there wasn't an ending THEN) warn and do nothing.
    return interpreter.err "#{SYNTAX} 'IF' without closing 'THEN'" unless @good
    return if underflow?(interpreter)

    if interpreter.stack.pop.zero?
      interpreter.interpret_line(@false_block.dup, true)
    else
      interpreter.interpret_line(@true_block.dup, true)
    end
  end

  private

  def read_true(line)
    loop do
      line = @source.gets.split if line.empty? && !@stop_if_empty
      return [] unless check_good(line)
      next unless (word = line.shift)
      return read_until(line, @false_block, 'then') if word.downcase == 'else'
      break if word.downcase == 'then'

      line = add_to_block(@true_block, word, line)
    end
    line
  end
end

# Implements a DO loop. Reads into the @block until a LOOP is found.
# On calling eval it pops two values off the stack: the start and end values
# for the loop. (End non-inclusive) From this it builds the sequence
# of blocks needed to execute the loop. For each iteration, it duplicates
# the base block, and replaces any I in the block with the current iteration value.
class ForthDo < ForthControlWord
  def initialize(*args)
    super(*args, end_word: 'loop')
  end

  def eval(interpreter)
    return interpreter.err "#{SYNTAX} 'DO' without closing 'LOOP'" unless @good
    return if underflow?(interpreter, 2)

    (limit, start) = interpreter.stack.pop(2)
    return warn "#{BAD_LOOP} Invalid loop range" if start.negative? || limit.negative? || start > limit

    do_loop(interpreter, start, limit)
  end

  private

  # for each iteration from start to limit, set I to the current value,
  # and interpret the block using the interprer
  def do_loop(interpreter, start, limit)
    (start...limit).each do |i|
      block = @block.dup.map { |w| w.is_a?(String) && w.downcase == 'i' ? i.to_s : w }
      interpreter.interpret_line(block, true)
    end
  end
end

# Implements a BEGIN loop. Reads into the block until an UNTIL is found.
# Evaluates by repeatedy popping a value off the stack and evaluating
# its block until the value is non-zero.
class ForthBegin < ForthControlWord
  def initialize(*args)
    super(*args, end_word: 'until')
  end

  def eval(interpreter)
    return interpreter.err "#{SYNTAX} 'BEGIN' without closing 'UNTIL'" unless @good

    # This should be the equivalent of the UNTIL popping the stack
    # and restarting at the BEGIN if non-zero.
    loop do
      interpreter.interpret_line(@block.dup, true)

      # NOTE: Should STACK_UNDERFLOW be raised if the stack is empty, or should the loop just halt?
      return if underflow?(interpreter)
      break unless interpreter.stack.pop.zero?
    end
  end
end

# loads and runs a file.
class ForthLoadFile < ForthKeyWord
  def initialize(line, *)
    @filename = line.shift
    super(line)
  end

  def eval(interpreter)
    return interpreter.err "#{BAD_LOAD} No filename given" unless @filename

    interpreter.load(@filename)
  end
end

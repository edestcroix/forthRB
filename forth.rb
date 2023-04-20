# TODO: Add comments
# - Only print newlines in output when neccessary.
# - Check that AND OR, and XOR do what they're supposed to.
# - IF parser (Do as a class?)
# - Loop parser (Do as a class?)

# NOTE: Idea for IF and LOOP
# When the IF/LOOP keywores are found, enter their
# parsers like for the words and strings, but store them into a class.
# Once the IF/LOOP is parsed, it is returned, and then
# call the newly created classes eval() method and pass it the stack as an argument.
# Then the classes can figure out what to evaluate. This shouldn't be too hard for regular parsing,
# but when evaluating a user word it might get tricky. Either save the raw IF/LOOP in the word,
# or build the classes during parsing and store them in the word, and have special cases for evaluating them.
# If done with the latter, could store strings as classes too.

# Put this in a mixin for organization purposes.
module Maths
  def add
    mathop(:+)
  end

  def sub
    mathop(:-)
  end

  def mul
    mathop(:*)
  end

  def div
    mathop(:/)
  rescue ZeroDivisionError
    0
  end

  def and
    mathop(:&)
  end

  def or
    mathop(:|)
  end

  def xor
    mathop(:^)
  end
end

# Implements Forth operations over top a Ruby array.
class ForthStack < Array
  include Maths

  def initialize(*args)
    super(*args)
  end

  def cr
    puts ''
  end

  def dot
    op = pop
    print "#{op} " unless check_nil([op])
  end

  def drop
    pop
  end

  def dump
    print self
    puts ''
  end

  def dup
    op = pop
    insert(-1, op, op) unless check_nil([op])
  end

  def emit
    # print ASCII of the top of the stack
    op = pop
    print "#{op.to_s.codepoints[0]} " unless check_nil([op])
  end

  def equal
    op1 = pop
    op2 = pop
    (push op1 == op2 ? -1 : 0) unless check_nil([op1, op2])
  end

  def greater
    op1 = pop
    op2 = pop
    (push op2 < op1 ? -1 : 0) unless check_nil([op1, op2])
  end

  def invert
    push(~pop)
  end

  def lesser
    op1 = pop
    op2 = pop
    (push op2 < op1 ? -1 : 0) unless check_nil([op1, op2])
  end

  def over
    op1 = pop
    op2 = pop
    insert(-1, op2, op1) unless check_nil([op1, op2])
  end

  def rot
    op1 = pop
    op2 = pop
    op3 = pop
    insert(-1, op2, op1, op3) unless check_nil([op1, op2, op3])
  end

  def swap
    op1 = pop
    op2 = pop
    insert(-1, op1, op2) unless check_nil([op1, op2])
  end

  private

  def mathop(opr)
    op1 = pop
    op2 = pop
    push(op2.send(opr, op1)) unless check_nil([op1, op2])
  end

  # if any of the operands are nil, return true,
  # and put the ones that aren't back on the stack
  def check_nil(ops)
    ops.each do |op|
      next unless op.nil?

      warn 'Stack underflow'
      ops.reverse.each { |o| o.nil? ? nil : push(o) }
      return true
    end
    false
  end
end

# Holds a forth IF statement. Calling read_line will start parsing
# the IF statement starting with the line given. Reads into
# the true_block until an ELSE or THEN is found, then reads into
# the false_block until a THEN is found if an ELSE was found.
# If another IF is encountered, creates a new ForthIf class,
# and starts it parsing on the rest of the line, resuming it's
# own parsing where that IF left off.
class ForthIf
  def initialize
    @true_block = []
    @false_block = []
  end

  # NOTE: Does it need to parse loops? Two ways to do this:
  # 1 - Have the IF create LOOP objects when loops are found.
  # 2 - Completely ignore them, and have them be constructed
  # during evaluation of the IF block.

  def eval(stack)
    puts "True block: #{@true_block}"
    puts "False block: #{@false_block}"
    top = stack.pop
    return warn 'Stack underflow' if top.nil?
    return @false_block if top.zero?

    @true_block
  end

  def read_line(line)
    read_true(line)
  end

  private

  def read_true(line)
    read_true($stdin.gets.split) if line.empty?
    word = line.shift
    return [] if word.nil?

    word = word.downcase
    return line if word == 'then'
    return read_false(line) if word == 'else'

    read_true(add_to_block(@true_block, word, line))
  end

  def add_to_block(block, word, line)
    if word == 'if'
      new_if = ForthIf.new
      line = new_if.read_line(line)
      block << new_if
    else
      block << word
    end
    line
  end

  def read_false(line)
    puts 'reading true'
    read_true($stdin.gets.split) if line.empty?
    word = line.shift
    return [] if word.nil?

    word = word.downcase
    read_false(add_to_block(@false_block, word, line)) if word != 'then'
    line
  end
end

@stack = ForthStack.new
@user_words = {}
@symbol_map = { '+' => 'add', '-' => 'sub', '*' => 'mul', '/' => 'div',
                '=' => 'equal', '.' => 'dot', '<' => 'lesser', '>' => 'greater' }

def interpret
  print '> '
  $stdin.each_line do |line|
    %W[quit\n exit\n].include?(line) ? exit(0) : interpret_line(line.split)
    puts 'ok'
    print '> '
  end
end

# Recursevely iterates over the line passed to it,
# evaluating the words as it goes. When encountering user
# defined words, calls eval_user_word. When encountering string
# or user word definition start characters, passes the rest of the list
# into the appropriate interpreters.
def interpret_line(line)
  return if line.nil? || line.empty?

  word = line.shift.downcase
  if @user_words.key?(word.to_sym)
    # eval_user_word consumes its input. Have to clone it.
    eval_user_word(@user_words[word.to_sym].map(&:clone))
    interpret_line(line) unless line.empty?
  else
    dispatch(line, word)
  end
end

# figures out what to do with non-user defined words.
# (because user defined words are the easy ones)
def dispatch(line, word)
  case word
  when '."'
    # eval_string returns the line after the string,
    # so continue the interpreter on this part.
    interpret_line(eval_string(line))
  when ':'
    interpret_line(interpret_word(line))
  when '('
    interpret_line(eval_comment(line))
  when 'if'
    interpret_line(eval_if(line))
  else
    eval_word(word, true)
    interpret_line(line)
  end
end

def eval_if(line)
  new_if = ForthIf.new
  line = new_if.read_line(line)
  eval_user_word(new_if.eval(@stack))
  line
end

# evaluate lines until the ":", at which point initialize a new word
# with the next element in the line as the key, then read every
# word until a ";" is found into the user_words hash.
def interpret_word(line)
  return warn 'Empty word definition' if line.empty?

  name = line[0].downcase.to_sym
  # This blocks overwriting system keywords, while still allowing
  # for user defined words to be overwritten.
  if @stack.respond_to?(name) || @symbol_map.key?(name.to_sym) || name =~ /\d+/
    warn "Word already defined: #{name}"
  else
    @user_words.store(name, [])
    read_word(line[1..], name)
  end
end

# TODO: Prevent certain words from being
# added to user defined words. In particular,
# don't allow word definition inside a word definition.
# Might also be good to have error checking
# while defining the word, not just when evaluating it. But
# that's less important.

# read words from stdin until a ';', storing
# each word in the user_words hash under 'name'
def read_word(line, name)
  read_word($stdin.gets.split, name) if line.empty?
  word = line.shift
  return line if word == ';'
  return [] if word.nil?

  @user_words[name].push(word)
  read_word(line, name)
end

# prints every word in the line until a " is found,
# then returns the rest of the line.
def eval_string(line)
  if line.include?('"')
    print line[0..line.index('"') - 1].join(' ')
    print ' '
    line[line.index('"') + 1..]
  else
    warn 'No closing " found'
  end
end

def eval_comment(line)
  return warn 'No closing ) found' unless line.include?(')')

  line[line.index(')') + 1..]
end

# evaluate a word. If it's a number, push it to the stack,
# and print it. Otherwise, if it is a symbol in the symbol_map,
# call the corresponding method on the stack from the symbol_map.
# Otherwise, if it is a method on the stack, call it.
# If it is none of these, warn the user.
def eval_word(word, print)
  if word.to_i.to_s == word
    print "#{word} " if print
    @stack.push(word.to_i)
  elsif @symbol_map.key?(word)
    @stack.send(@symbol_map[word].to_sym)
  elsif valid_word(word)
    @stack.send(word.to_sym)
  else
    warn "Unknown word: #{word}"
  end
end

# checks if the word is a valid word. This is done to make sure keywords that are Ruby array
# methods don't get called. (Before eval_word just tested for stack.respond_to?
# which caused problems) Only checks for specific keywords, because at this point
# it has already been checked for being a user word, or a number or symbol.
def valid_word(word)
  return false if word.nil?
  return false if word == ';'
  return false unless %w[cr drop dump dup emit invert over rot swap].include?(word)

  true
end

# Iterate over the user defined word, evaluating each word
# in the list. Can evaluate strings currently.
# TODO: Once LOOPs are implemented,
# this will have to handle them somehow.
def eval_user_word(word_list)
  return if word_list.nil? || word_list.empty?

  w = word_list.shift
  # yes, I made a weird function just so I could make this a one liner.
  return eval_if_and_cont(w, proc { eval_user_word(word_list) }) if w.is_a?(ForthIf)

  case w.downcase
  when '."'
    eval_user_word(eval_string(word_list))
  when '('
    eval_user_word(eval_comment(word_list))
  when 'if'
    eval_user_word(eval_if(word_list))
  else
    eval_word(w.downcase, false)
    eval_user_word(word_list) unless word_list.empty?
  end
end

def eval_if_and_cont(if_obj, continute_func)
  eval_user_word(if_obj.eval(@stack))
  continute_func.call
end

interpret

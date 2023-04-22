# frozen_string_literal: true

require_relative 'forth_methods'

# Source is a wrapper around the input source, so that
# the interpreter can get its input from an abstracted
# interface. This allows it to read from a file or stdin,
# and also allows it to print the prompt before each line.
# This way, the interpreter itself does not have to
# deal with prompts, it only has to call gets on the source,
# and the source will handle the prompt and printing as requested.
# If the source is initialized with alt_print set to true,
# it will never print a prompt, and instead print the line it gets.
class Source
  def initialize(source, alt_print: false)
    @source = source
    @print_line = alt_print
  end

  def gets(print: false)
    # only print the prompt if print is true
    print '> ' if print && !@print_line
    line = @source.gets
    puts "> #{line}" if @print_line
    line
  end
end

# Methods for the ForthInterpreter that handle word evaluation, other
# than custom word definitions. Moved to a module so rufocop
# would stop complaining about the class being too long.
module ForthEvaluators
  # maps the various types of words to their respective functions.
  def func_map
    { ':' => proc { |x| create_word(x) } }
  end

  # Evaluates basic Forth words. (I.e the default single word operators,
  # not strings, IF's, word defs, etc.) Pushes numbers onto the stack, evals
  # the word on the stack if the word is present in either the symbol_map or
  # in the keywords list. Otherwise sends the appropriate error message.
  def eval_word(word)
    if word.to_i.to_s == word
      @stack.push(word.to_i)
    elsif @symbol_map.key?(word)
      @stack.send(@symbol_map[word].to_sym)
    elsif @heap.defined?(word)
      @stack.push(@heap.get_address(word))
    elsif @constants.key?(word.to_sym)
      @stack.push(@constants[word.to_sym])
    elsif valid_word(word)
      @stack.send(word.to_sym)
    end
  end

  private

  # checks if the word is a valid word. This is done to make sure keywords that are Ruby array
  # methods don't get called. (Before eval_word just tested for stack.respond_to?
  # which caused problems) Only checks for specific keywords, because at this point
  # it has already been checked for being a user word, or a number or symbol.
  def valid_word(word)
    return false if word.nil?
    return warn "#{SYNTAX} ';' without opening ':'" if word == ';'
    return warn "#{SYNTAX} 'LOOP' without opening 'DO'" if word == 'loop'
    return warn "#{SYNTAX} '#{word.upcase}' without opening 'IF'" if %w[else then].include?(word)
    return warn "#{BAD_WORD} Unknown word '#{word}'" unless @keywords.include?(word)

    true
  end
end

# Main interpreter class. Holds the stack, and the dictionary of
# user defined words. The dictionary is a hash of words to arrays
# of words. Two methods are public: interpret and interpret_line.
# interpret repeatedly calls interpret_line on lines read
# from the source definied on creation. interpret_line takes
# an array of words and evaluates them on the stack.
class ForthInterpreter
  include ForthEvaluators
  attr_reader :stack, :heap, :constants

  def initialize(source)
    @source = source
    @stack = []
    @heap = ForthHeap.new
    @constants = {}
    @user_words = {}
    @func_map = func_map
    @keywords = %w[cr drop dump dup emit invert over rot swap variable constant allot cells if do begin]
    @symbol_map = { '+' => 'add', '-' => 'sub', '*' => 'mul', '/' => 'div',
                    '=' => 'equal', '.' => 'dot', '<' => 'lesser', '>' => 'greater',
                    '."' => 'string', '(' => 'comment', '!' => 'set_var', '@' => 'get_var' }
  end

  # starting here, a line is read in from stdin. From this point, various recursive calls
  # are made to parse the line and evaluate it. The main function, interpret_line,
  # recursively iterates over the input line, and in the basic case just calls eval_word
  # to perform a simple action on the stack. If it is something more complicated like a
  # comment or string, it calls another method, which reads the line the same way as
  # interpret_line, but performs different actions. When these functions find the word
  # that terminates the block they are reading, they return whatever is after back out,
  # and another recursive interpret_line call is made on whatever comes after.

  def interpret
    while (line = @source.gets(print: true))
      %W[quit\n exit\n].include?(line) ? exit(0) : interpret_line(line.split, false)
      puts 'ok'
    end
  end

  # Interprets a line of Forth code. line is an array of words.
  # bad_on_empty determines whether parsers should warn if they find an empty line,
  # or keep reading from stdin until the reach their terminating words.
  def interpret_line(line, bad_on_empty)
    return if invalid_line?(line)

    if (w = line.shift).is_a?(ForthObj)
      # pass self to the object so it can call interpret_line
      # however it wants. (E.g a Do Loop will call it multiple times,
      # an IF will call it on either it's true or false block.)
      w.eval(self)
    elsif @user_words.key?(w.downcase.to_sym)
      # eval_user_word consumes its input. Have to clone it.
      interpret_line(@user_words[w.downcase.to_sym].dup, true)
    else
      line = dispatch(w, line, bad_on_empty)
    end
    interpret_line(line, bad_on_empty)
  end

  def system?(word)
    @keywords.include?(word) || @symbol_map.key?(word)\
    || @user_words.key?(word.to_sym) || @constants.key?(word)
  end

  private

  # putting this here instead of just having in interpret_line directly
  # stopped rufocop from having a hissy fit for ABC complexity so I've left it.
  def invalid_line?(line)
    line.nil? || line.empty?
  end

  # Calls the appropriate function based on the word.
  def dispatch(word, line, bad_on_empty)
    w = word

    if @func_map.key?((w = w.downcase))
      @func_map.fetch(w).call(line)
    elsif (new_obj = klass(name(w)))
      eval_obj(new_obj, line, bad_on_empty)
    else
      eval_word(w)
      line
    end
  end

  def name(word)
    word = if (w = @symbol_map[word.downcase])
             w
           elsif !@keywords.include?(word.downcase)
             'bad'
           else
             word
           end
    "Forth#{word.split('_').map!(&:capitalize).join('')}"
  end

  def eval_obj(obj, line, bad_on_empty)
    (new_obj = obj.new(line, @source, bad_on_empty)).eval(self)
    new_obj.remainder
  end

  # evaluate lines until the ":", at which point initialize a new word
  # with the next element in the line as the key, then read every
  # word until a ";" is found into the user_words hash.
  def create_word(line)
    return warn "#{BAD_DEF} Empty word definition" if line.empty?

    name = line[0].downcase.to_sym
    # This blocks overwriting system keywords, while still allowing
    # for user defined words to be overwritten.
    if system?(name) && !@user_words.key?(name)
      warn "#{BAD_DEF} Word already defined: #{name}"
    else
      @user_words.store(name, [])
      read_word(line[1..], name)
    end
  end

  # read words from stdin until a ';', storing
  # each word in the user_words hash under 'name'
  def read_word(line, name)
    read_word(@source.gets.split, name) if line.empty?
    word = line.shift
    return line if word == ';'
    return [] if word.nil?

    @user_words[name].push(word)
    read_word(line, name)
  end

  def klass(class_name)
    Module.const_get(class_name)
  rescue NameError
    nil
  end
end

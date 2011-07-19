# An experiemental CoffeeScript Lexer.
# 
# Tokens are produced in the form:
#
#       [tag, value, lineNumber]

{Rewriter} = require './rewriter'

# The Lexer Class
# ---------------
#
# The Lexer class reads a stream of CoffeeScript and divvvies it up into tagged
# tokens.  Some potential ambiguity in the grammer has been avoided by 
# pushing some extra smarts into the Lexer.
exports.Lexer = class Lexer
    @rules = {}

    constructor: ->
        @tokens = []
        @line = 1
        @code = ""

    # **tokenize** is the Lexer's main method
    tokenize: (code, opts = {}) ->
        i = 0
        while c = code.charAt i
            context = {input:code, pos:i, line:@line, char:c, err:null}
            rules = [Lexer.rules[c]]
            rules = Lexer.rules[0] unless rules[0]?
            (token = rule.tokenize(context); break if token?) for rule in rules
            
            throw new Error "Don't know what to do with #{c} on line #{@line} at position #{i}" if not token?
            @line = context.line
            @tokens.push token
            throw new Error context.err if context.err?
            i = context.pos

        @tokens
    
     

exports.LexerRule = class LexerRule
    constructor: (@state, @initialChars, @regex, @after = null, @fn = null) ->
        @fn = @defaultFn if not @fn?

    defaultFn: (context) ->
        match = if @regex?
            @regex.lastIndex = context.pos
            @regex.exec context.input
        
        match or= unless match?
            m =[context.char]
            m['index'] = context.pos
            m

        return null if context.pos isnt match.index or match[0].length == 0

        context.pos += match[0].length
        token = [@state, match[0], context.line]
        token = @after(token, context) if @after?
        token

    tokenize: (context) ->
        token = @fn(context)
        token

# A DSL similar to the CoffeeScript Grammar DSL for defining lexer rules
o = (state, opts) ->
    {chars, regex, after} = opts
    if chars?
        Lexer.rules[char] = new LexerRule(state, chars, regex, after) for char in chars
    else
        Lexer.rules[0] = others = [] unless (others = Lexer.rules[0])
        others.push new LexerRule(state, '', regex, after)


o 'WHITESPACE',
    chars:          ' \t'

o 'NEWLINE',
    chars:          '\n'
    after:          (token, context) ->  context.line++

o 'COMMENT',
    chars:          '#'
    regex:          /###([^#][\s\S]*?)(?:###[^\n\S]*|(?:###)?$)|(?:#(?!##[^#]).*)+|/g

o 'STRING',
    chars:          '\'"'

o 'NUMBER',
    regex:          ///
                    0x[\da-f]+ |                                # hex
                    \d*\.?\d+ (?:e[+-]?\d+)?                    # decimal
                    |///ig

o 'IDENTIFIER',
    regex:          ///
                    ( [$A-Za-z_\x7f-\uffff][$\w\x7f-\uffff]* )
                    ( [^\n\S]* : (?!:) )?  # Is this a property name?
                    |///g

#console.log Lexer.rules

sample = "  ' ababab \t\n\t \" 877 \n# and then here comes a long comment\n d b a 32.4"

# ANSI Terminal Colors.
bold  = '\033[0;1m'
red   = '\033[0;31m'
green = '\033[0;32m'
reset = '\033[0m'
fmt    = (ms) -> " #{bold}#{ "   #{ms}".slice -4 }#{reset} ms"

# Time the lexer
now = Date.now()
time   = -> ms = -(now - now = Date.now()); fmt ms
l = new Lexer()
tokens = l.tokenize(sample)
time_taken = "Lexing occurred in #{time()}"
console.log tokens
console.log time_taken

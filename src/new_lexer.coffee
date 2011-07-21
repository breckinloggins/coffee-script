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
    @others = []

    constructor: (@line = 1, @rules = Lexer.rules, @others = Lexer.others) ->
        @tokens = []
        @code = ""
        @count = 0

    # **tokenize** is the Lexer's main method
    tokenize: (code, opts = {}) ->
        i = if opts.start? then opts.start else 0
        while c = code.charAt i
            context = {input:code, pos:i, line:@line, char:c, err:null}
            rules = @rules[c]
            (tokens = rule.tokenize(context); break if tokens?) for rule in rules if rules?

            if not rules? or (rules? and not tokens?)
                (tokens = rule.tokenize(context); break if tokens?) for rule in @others

            throw new Error context.err if context.err?
            throw new Error "Don't know what to do with #{c} on line #{@line} at position #{i}" if not tokens?
            @line = context.line
            @tokens.push token for token in tokens
            i = context.pos
        
        @count = i
        @tokens
    
     

exports.LexerRule = class LexerRule
    constructor: (@state, @initialChars, @regex, @balanced = no, @after = null, @fn = null) ->
        @fn = @defaultFn if not @fn?

    unbalanced: (char) ->
        regex = new RegExp "#{char}[^#{char}]*#{char}|", "g"
        new LexerRule(@state, char, regex, no, @after, @fn)

    defaultFn: (context) ->
        match = if @regex?
            @regex.lastIndex = context.pos
            @regex.exec context.input
        
        match or= unless match?
            m =[context.char]
            m['index'] = context.pos
            m

        return null if context.pos isnt match.index or match[0].length == 0
        
        if @balanced
            balancedToken = @unbalanced(context.input.charAt context.pos).tokenize(context)
            if not balancedToken?
                context.err = new Error "Unbalanced #{context.input.charAt context.pos} on column #{context.pos}, line #{context.line}"
                return null
            else
                return balancedToken
        
        context.pos += match[0].length
        token = [@state, match[0], context.line]
        token = @after(token, context) if @after?
        [token]

    tokenize: (context) ->
        tokens = @fn(context)
        tokens

# A DSL similar to the CoffeeScript Grammar DSL for defining lexer rules
o = (state, opts) ->
    {chars, regex, after, balanced} = opts
    if chars?
        (Lexer.rules[char] = [] unless Lexer.rules[char]?) for char in chars
        Lexer.rules[char].push new LexerRule(state, chars, regex, balanced, after) for char in chars
    else
        Lexer.others.push new LexerRule(state, '', regex, balanced, after)


o 'WHITESPACE',
    chars:          ' \t'

o 'NEWLINE',
    chars:          '\n'
    after:          (token, context) ->  context.line++; token

o 'COMMENT',
    chars:          '#'
    regex:          /###([^#][\s\S]*?)(?:###[^\n\S]*|(?:###)?$)|(?:#(?!##[^#]).*)+|/g

o 'CALL',
    chars:          '-='
    regex:          /[-=]>|/g

o 'MINUS',
    chars:          '-'

o 'STRING',
    chars:          '\'"'
    balanced:       yes

o 'JS',
    chars:          '`'
    balanced:       yes

o 'COMPOUND_ASSIGN',
    chars:          '=-+/*%|&?<>^'
    regex:          ///
                    [-+*/%<>&|^!?=]=|                           # "unary" compounds
                    ([|&<>])\1=|                               # double compounds
                    >>>=?
                    |///g

o 'UNARY',
    chars:          '!~ntd'
    regex:          ///
                    !|
                    ~|
                    new|
                    typeof|
                    delete|
                    do 
                    |///g

o 'LOGIC',
    chars:          '&|^'
    regex:          /([&|])\1|[&|^]|/g

o 'SHIFT',
    chars:          '<>'
    regex:          /<<|>>|>>>|/g

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

sample = "  ' ababab ' \t\n\t  << >> >>> typeof && ^ 877 & | == &= \" \" || ||= ^= foo->bar=>bar - NEW baz -> `some javascript()`\n# and then here comes a long comment\n d b a 32.4"

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

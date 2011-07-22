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

        @tokens.last = -> if @length > 0 then @[@length-1] else null

    # **tokenize** is the Lexer's main method
    tokenize: (code, opts = {}) ->
        i = if opts.start? then opts.start else 0
        context = {input: code, pos:i, line:@line, tokens:@tokens, states:[], err:null}
        
        while c = code.charAt i
            context.char = c
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
    constructor: (@tag, @initialChars, @regex, @balanced = no, @after = null, @fn = null) ->
        @fn = @defaultFn if not @fn?

    unbalanced: (char) ->
        regex = new RegExp "#{char}[^#{char}]*#{char}|", "g"
        new LexerRule(@tag, char, regex, no, @after, @fn)

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
        token = [@tag, match[0], context.line]
        token = @after(token, context) if @after?
        [token]

    tokenize: (context) ->
        tokens = @fn(context)
        tokens

# A DSL similar to the CoffeeScript Grammar DSL for defining lexer rules
o = (tag, opts = {}) ->
    {chars, regex, after, balanced} = opts
    chars = tag if not chars? and not regex?
    if chars?
        (Lexer.rules[char] = [] unless Lexer.rules[char]?) for char in chars
        Lexer.rules[char].push new LexerRule(tag, chars, regex, balanced, after) for char in chars
    else
        Lexer.others.push new LexerRule(tag, '', regex, balanced, after)

###
COFFEESCRIPT SYNTAX DEFINITION
###
# NOTE: Order matters.  It would be nice to determine order automatically based on the length of the regex
# TODO: Leave off the end | and the g option on the regexes and have the DSL put those in
# TODO: Nicer syntax for keywords, including automatically setting the initial chars

o 'WHITESPACE',
    chars:          ' \t'
    regex:          /([ \t])+|/g
    after:          (token, context) ->
        # Replace the terminator and whitespace with an INDENT or OUTDENT token if necessary
        if context.tokens.last()?[0] == 'TERMINATOR' and context.tokens.last()?[1] == '\n' and context.indent isnt token[1].length
            token[0] = if not context.indent? or context.indent < token[1].length then 'INDENT' else 'OUTDENT'
            context.indent = token[1] = token[1].length
            context.tokens.pop()
        token

o 'TERMINATOR',
    chars:          '\n'
    after:          (token, context) ->  context.line++; token

o 'COMMENT',
    chars:          '#'
    regex:          /###([^#][\s\S]*?)(?:###[^\n\S]*|(?:###)?$)|(?:#(?!##[^#]).*)+|/g

o '('
o ')'
o '{'
o '}'
o ';',
    after:          (token, context) -> token[0] = 'TERMINATOR'; token

o 'SHIFT',
    chars:          '<>'
    regex:          /<<|>>|>>>|/g

o 'COMPARE',
    chars:          '=!<>'
    regex:          /// [<>!]=?| ///g

o 'CALL',
    chars:          '-='
    regex:          /[-=]>|/g

o 'HEREDOC',
    chars:          '\'"'
    regex:          /// ("""|''') ([\s\S]*?) (?:\n[^\n\S]*)? \1 |///g

o 'STRING',
    chars:          '\'"'
    balanced:       yes

o 'JSTOKEN',
    chars:          '`'
    balanced:       yes

o 'COMPOUND_ASSIGN',
    chars:          '=-+/*%|&?<>^'
    regex:          ///
                    [-+*/%<>&|^!?=]=|                           # "unary" compounds
                    ([|&<>])\1=|                                # double compounds
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

o 'DOUBLES',
    chars:          '-+:'
    regex:          /([-+:])\1|/g

o 'HEREGEX',
    chars:          '/'
    regex:          /// /{3} ([\s\S]+?) /{3} ([imgy]{0,4}) (?!\w) |///g

o 'REGEX',
    chars:          '/'
    regex:          ///
                    / (?! [\s=] )                               # Disallow leading whitespace or equals signs
                    [^ [ / \n \\]*                              # Every other string
                    (?:
                        (?: \\[\s\S]                            # Anything escaped
                        | \[                                    # Character class
                                [^ \] \n \\ ]*
                                (?: \\[\s\S] [^ \] \n \\ ]* )*
                            ]
                        ) [^ [ / \n \\ ]*
                    )*
                    / [imgy]{0,4} (?!\w)
                    |///g

o 'MATH',
    chars:          '+*/%'

o 'MINUS',
    chars:          '-'

o 'LOGIC',
    chars:          '&|^'
    regex:          /([&|])\1|[&|^]|/g

o 'RESERVED',
    chars:          'cdfvwlein_'
    regex:          ///
                    case|
                    default|
                    function|
                    var|
                    void|
                    with|
                    const|
                    let|
                    enum|
                    export|
                    import|
                    native|
                    __hasProp|
                    __extends|
                    __slice|
                    __bind|
                    __indexOf
                    |///g
    after:          (token, context) -> context.err = "Reserved word \"#{token[1]}\" on line #{context.line}"; null

o 'JS_KEYWORDS',
    chars:          'tfndirbcesw'
    regex:          ///
                    this|
                    new|
                    delete|
                    return|
                    throw|
                    break|
                    continue|
                    debugger|
                    if|
                    else|
                    switch|
                    for|
                    while|
                    try|
                    catch|
                    finally|
                    class|
                    extends|
                    super
                    |///g
    after:          (token, context) -> token[0] = token[1].toUpperCase(); token

o 'COFFEE_KEYWORDS',
    chars:          'utlobw'
    regex:          ///
                    undefined|
                    then|
                    unless|
                    until|
                    loop|
                    of|
                    by|
                    when
                    |///g
    after:          (token, context) -> token[0] = token[1].toUpperCase(); token

o 'RELATION',
    chars:          'io'
    regex:          ///instanceof|of|in|///g

o 'BOOL',
    chars:          'tfnu'
    regex:          ///true|false|null|undefined|///g

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

###
TESTING
###
#console.log Lexer.rules

sample = "  ' ababab '        \t\n\t \n  \n    ///hello /// /something/ ///something \n else///igy 2 <= 3; 4 != 5 3 >= < > 4 << >> >>> typeof && ^ 877 & | == &= \" \" || ||= ^= foo->bar=>bar - NEW baz -> `some javascript()`\n# and then here comes a long comment\n d b a 32.4 i++ this::that --foo 3+2-4/5%3 in of instanceof true false null undefined (hello) { a block } \"\"\" a heredoc \"\"\" ''' another \n heredoc ''' #case something\n undefined"

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

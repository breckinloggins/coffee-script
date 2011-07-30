# An experiemental CoffeeScript Lexer.
# 
# Tokens are produced in the form:
#
#       [tag, value, lineNumber]

{Rewriter} = require './rewriter'
fs = require 'fs'

# ANSI Terminal Colors.
bold  = '\033[0;1m'
red   = '\033[0;31m'
green = '\033[0;32m'
reset = '\033[0m'
fmt    = (ms) -> " #{bold}#{ "   #{ms}".slice -4 }#{reset} ms"

class SyntaxError extends Error
    constructor: (@context, @err) ->

    toString: () ->
        startIdx = @context.pos - 10
        startIdx = 0 unless startIdx >= 0
        output = "#{red}Syntax Error:#{reset} #{bold}#{@err}#{reset} on column #{bold}#{@context.pos}#{reset}, line #{bold}#{@context.line}#{reset}\n"
        output += "Around \"#{@context.input.substr(startIdx, 40).replace(/\n/mg, " ")}\"\n"
        output += "       "
        (output += " ") for i in [@context.pos..startIdx]
        output += "#{red}^#{reset}\n\n"
        output

# The Lexer Class
# ---------------
#
# The Lexer class reads a stream of CoffeeScript and divvvies it up into tagged
# tokens.  Some potential ambiguity in the grammer has been avoided by 
# pushing some extra smarts into the Lexer.
exports.Lexer = class Lexer

    constructor: (@line = 1, @rules = {}, @others = []) ->
        @syntax = ""
        @tokens = []
        @code = ""
        @count = 0

        @tokens.last = -> if @length > 0 then @[@length-1] else null

    # **tokenize** is the Lexer's main method
    tokenize: (code, opts = {}) ->
        i = if opts.start? then opts.start else 0
        context = {input: code, pos:i, line:@line, tokens:@tokens, states:[], done: no, err:null}

        while (c = code.charAt i) and not context.done
            context.char = c
            rules = @rules[c]
            (tokens = rule.tokenize(context); break if tokens?) for rule in rules if rules?

            if not rules? or (rules? and not tokens?)
                (tokens = rule.tokenize(context); break if tokens?) for rule in @others
            
            throw new Error context.err if context.err?
            throw new Error new SyntaxError context, "Don't know what to do with \"#{c}\"" if not tokens?
            @line = context.line
            @tokens.push token for token in tokens
            i = context.pos
        
        @tokens
        return @tokens if opts.rewrite is off
        (new Rewriter).rewrite @tokens
    
    copy: ->
        l = new Lexer

        # NOTE: This won't do if we have dynamically modfiying lexers
        l.rules = @rules
        l.others = @others

        l
     

exports.LexerRule = class LexerRule
    constructor: (@tag, @initialChars, @regex, @balanced = no, @after = null, @fn = null) ->
        @fn = @defaultFn if not @fn?

    unbalanced: (char) ->
        regex = new RegExp "(?:#{char})([^#{char}]*)(?:#{char})|", "g"
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
                context.err = new SyntaxError context, "Unbalanced \'#{context.input.charAt context.pos}\'"
                return null
            else
                return balancedToken
       
        captured = if match[1]? then match[1] else match[0]
        return null unless captured?

        context.pos += match[0].length
        token = [@tag, captured, context.line]
        token = @after(token, context) if @after?
        [token]

    tokenize: (context) ->
        tokens = @fn(context)
        tokens

# A DSL similar to the CoffeeScript Grammar DSL for defining lexer rules
syntaxes = {}
currentLexer = null

syntax_for = (name) ->
    l = new Lexer
    l.syntax = name
    syntaxes[name] = l
    currentLexer = l

o = (tag, opts = {}) ->
    throw new Error "Please declare a syntax name using 'syntax_for' before defining syntax rules" if not currentLexer?
    
    {chars, regex, after, syntax, balanced} = opts
    
    if syntax?
        nextLexer = if typeof syntax is 'string' then syntaxes[syntax] else new Lexer()

        after = (token, context) ->
            token
        
        if typeof syntax is 'function'
            prevLexer = currentLexer
            currentLexer = nextLexer
            syntax()
            currentLexer = prevLexer

    chars = tag if not chars? and not regex?
    (currentLexer.rules[char] = [] unless currentLexer.rules[char]?) for char in chars if chars?
    if chars? then for char in chars
        rules = currentLexer.rules[char]
        if regex?
            rules.unshift new LexerRule(tag, chars, regex, balanced, after)
        else
            throw new Error "Ambiguous pattern for '#{char}'" if rules.length > 0 and not rules[rules.length - 1].regex?
            rules.push new LexerRule(tag, chars, regex, balanced, after)
    else
        currentLexer.others.push new LexerRule(tag, '', regex, balanced, after)

###
COFFEESCRIPT SYNTAX DEFINITION
###
# TODO: Leave off the end | and the g option on the regexes and have the DSL put those in
# TODO: Nicer syntax for keywords, including automatically setting the initial chars

syntax_for "CoffeeScript"

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

#o '\\'
o ','
o '@'
o '='
o '.'
o '['
o ']'
o '('
o ')'
o '{'
o '}'
o '?'
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
    chars:          '\''
    balanced:       yes

o 'STRING',
    chars:          '"'
    balanced:       yes
    syntax:          ->
        o 'INTERPOLATE',
            chars:          '#'
            regex:          /#\{|/g
            syntax:         "CoffeeScript"
        o '\\',
            after:          (token, context) -> token[1]+=context.input[++context.pos]; ++context.pos; token
        o '#',
            after:          (token, context) -> context.done = yes
        o 'DEFAULT',
            regex:          /(?:[^\\]*)[^"]*|/g

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
                    default[^\w]|
                    function|
                    var|
                    void|
                    with|
                    const[^\w]|
                    let|
                    enum|
                    export[^\w]|
                    import|
                    native|
                    __hasProp|
                    __extends|
                    __slice|
                    __bind|
                    __indexOf
                    |///g
    after:          (token, context) -> context.err = new SyntaxError context, "Reserved word \"#{token[1]}\" on line #{context.line}"; null

o 'JS_KEYWORDS',
    # words:    .... instead of chars and regex
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

sample = "  abc ' ababab '     \t\n\t \n  \n    ///hello /// /something/ ///something \n else///igy 2 <= 3; 4 != 5 3 >= < > 4 << >> >>> typeof && ^ 877 & | == &= \" \" || ||= ^= foo->bar=>bar - NEW baz -> `some javascript()`\n# and then here comes a long comment\n d b a 32.4 i++ this::that --foo 3+2-4/5%3 in of instanceof true false null undefined (hello) { a block } \"\"\" a heredoc \"\"\" ''' another \n heredoc ''' #case something\n undefined"

# Time the lexer
l = syntaxes["CoffeeScript"]
now = Date.now()
time   = -> ms = -(now - now = Date.now()); fmt ms
if process.argv[2]?
    tokens = l.tokenize(fs.readFileSync(process.argv[2], "UTF-8"), rewrite:off)
else
    tokens = l.tokenize(sample, rewrite: off)
    
time_taken = "Lexing occurred in #{time()}"
console.log tokens
console.log time_taken

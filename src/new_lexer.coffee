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

# Prints syntax errors in a nice format and attempts to show you the approximate position that the error orccured
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
# The Lexer class reads a stream of CoffeeScript and divvies it up into tagged
# tokens.  Some potential ambiguity in the grammer has been avoided by 
# pushing some extra smarts into the Lexer.
exports.Lexer = class Lexer

    constructor: (@line = 1, @rules = {}, @others = []) ->
        @reset()
    
    # The lexer is stateful by default, so reset should be called before tokenizing a new 
    # input stream
    reset: ->
        @tokens = []
        @code = ""
        @pos = 0
        @endChar = null

        @tokens.last = -> if @length > 0 then @[@length-1] else null

    # **tokenize** is the Lexer's main method
    tokenize: (code, opts = {}) ->
        i = if opts.start? then opts.start else 0
        context = {input: code, pos:i, line:@line, tokens:@tokens, states:[], done: no, err:null}
        
        while (c = code.charAt i) and not context.done
            break if @endChar? and c is @endChar
            context.char = c
            rules = @rules[c]
            (tokens = rule.tokenize(context); break if tokens?) for rule in rules if rules?

            if not rules? or (rules? and not tokens?)
                (tokens = rule.tokenize(context); break if tokens?) for rule in @others
            
            throw new Error context.err if context.err?
            throw new Error new SyntaxError context, "Don't know what to do with \"#{c}\"" if not tokens? and i == context.pos
            @line = context.line
            @tokens.push token for token in tokens
            i = context.pos
       
        @pos = i
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
    constructor: (@tag, @initialChars, @regex, @after = null, @fn = null) ->
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
       
        captured = if match[1]? then match[1] else match[0]
        return null unless captured?

        context.pos += match[0].length
        token = [@tag, captured, context.line]
        token = @after(token, context) if @after?
        if token? and token.length > 0 and not (token[0] instanceof Array)
            # This is a regular token, wrap it in an array for convenience to the lexer
            [token]
        else
            # Already an array of tokens, don't wrap it
            token

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
    
    {chars, regex, after, syntax, keywords, end} = opts
    throw new Error "Cannot specify an end unless defining a subsyntax in tag #{tag}" if end? and not syntax?
    
    if keywords?
        # Keywords is a convenient macro so you're not allowed to further specify this stuff
        throw new Error "Cannot specify both keywords and a regex in tag #{tag}" if regex?
        throw new Error "Cannot specify both keywords and chars in tag #{tag}" if chars?
        throw new Error "Cannot specify both keywords and syntax in tag #{tag}" if syntax?
        throw new Error "Must specify at least one keyword in tag #{tag}" if keywords.length == 0
        
        keywordChars = {}
        regex = ""
        for keyword in keywords.split("\n")
            keywordChars[keyword.charAt 0] = null
            regex += "#{keyword}(?:[^\\S]|$)|"

        chars = []
        chars.push char for char, _ of keywordChars
        regex = new RegExp(regex, "g")

    if syntax?
        nextLexer = if typeof syntax is 'string' then syntaxes[syntax].copy() else new Lexer()
        nextLexer.endChar = end if end?
        after = (token, context) =>
            tokens = nextLexer.tokenize context.input, start:context.pos
            context.pos = nextLexer.pos
            tokens
        
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
            rules.push new LexerRule(tag, chars, regex, after)
        else
            throw new Error "Ambiguous pattern for '#{char}'" if rules.length > 0 and not rules[rules.length - 1].regex?
            rules.push new LexerRule(tag, chars, regex, after)
    else
        currentLexer.others.push new LexerRule(tag, '', regex, after)

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

o 'CALL',
    chars:          '-='
    regex:          /[-=]>|/g

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
o ';'
    after:          (token, context) ->
        token[0] = if token[1] == ';' then 'TERMINATOR' else token[1]
        token

o 'SHIFT',
    chars:          '<>'
    regex:          /<<|>>>|>>|/g

o 'COMPARE',
    chars:          '=!<>'
    regex:          /// [<>!]=?| ///g

o 'HEREDOC',
    chars:          '\'"'
    regex:          /// ("""|''') ([\s\S]*?) (?:\n[^\n\S]*)? \1 |///g

o 'STRING',
    chars:          '\''
    regex:          /'((?:\\'|[^'])*)'|/g

o 'STRING',
    chars:          '"'
    start:          /[^\\]"|/g
    syntax:         ->
        o 'STRING',
            regex: /((?:\\"|[^"#])*)["#]|/g
            after:  (token, context) -> context.done = yes; token
        o 'INTERPOLATE',
            chars:  '#'
            regex:  /#{|/g
            syntax: "CoffeeScript"
            end:    '}'
            after: (token, context) -> console.log "Woohoo?"; token
    after:          (token, context) -> console.log "Woohoo!"; token

o 'JSTOKEN',
    chars:          '`'
    regex:          /`((?:\\`|[^`])*)`|/g

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
                    ~
                    |///g

o 'UNARY',
    keywords:       """
                    new
                    typeof
                    delete
                    do
                    """

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
    keywords:       """
                    case
                    default
                    function
                    var
                    void
                    with
                    const
                    let
                    enum
                    export
                    import
                    native
                    __hasProp
                    __extends
                    __slice
                    __bind
                    __indexOf
                    """
    after:          (token, context) -> context.err = new SyntaxError context, "Reserved word \"#{token[1]}\" on line #{context.line}"; null

o 'JS_KEYWORDS',
    keywords:       """
                    this
                    new
                    delete
                    return
                    throw
                    break
                    continue
                    debugger
                    if
                    else
                    switch
                    for
                    while
                    try
                    catch
                    finally
                    class
                    extends
                    super
                    """
    after:          (token, context) -> token[0] = token[1].toUpperCase(); token

o 'COFFEE_KEYWORDS',
    keywords:       """
                    undefined
                    then
                    unless
                    until
                    loop
                    of
                    by
                    when
                    """
    after:          (token, context) -> token[0] = token[1].toUpperCase(); token

o 'RELATION',
    keywords:       """
                    instanceof
                    of
                    in
                    """

o 'BOOL',
    keywords:       """
                    true
                    false
                    null
                    undefined
                    """

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

# TODO: Move this to a separate file and integrate with CoffeeScript's test functionality
test = ->

    ok = (condition, message) ->
        throw new Error(message) unless condition

    tests = {}
    l = syntaxes["CoffeeScript"]
    t = (input) ->
        l.reset()
        l.tokenize input, rewrite:off
    
    # Lex the given input and ensure that the output tokens match the tokens given
    lex = (input, tokens, debug = false) ->
        output = t input
        console.log output if debug
        ok output.length == tokens.length, "token count should be #{tokens.length} but was #{output.length}"
        for token, i in output
            ok token[0] == tokens[i][0], "token #{i} type should be '#{tokens[i][0]}' but was '#{token[0]}'"
            ok token[1] == tokens[i][1], "token #{i} value should be '#{tokens[i][1]}' but was '#{token[1]}'"

        output

    ###
      Tests for individual lexer components
    ###
    tests['Empty Content'] = ->
        lex "", []

    tests['Just Whitespace'] = ->
        lex " ", [['WHITESPACE', " ", 1]]
        lex "  ", [['WHITESPACE', " ", 1]]  # Currently the lexer only reports the last whitespace char
        lex "\t", [['WHITESPACE', "\t", 1]]
        lex "   \t", [['WHITESPACE', "\t", 1]]
   
    tests['Terminator'] = ->
        lex "\n", [['TERMINATOR', "\n", 1]]
    
    tests['Comment'] = ->
        # TODO: The lexer SHOULD remove the first # character
        lex "# This is a comment", [['COMMENT', "# This is a comment", 1]]
        lex "#", [['COMMENT', "#", 1]]
        lex "## Another comment", [['COMMENT', "## Another comment", 1]]
        # TODO: The lexer SHOULD sanitize this to remove the indentation
        lex """
            ###
              A Block comment
              This is a block comment
            ###
            """,
            [['COMMENT', "\n  A Block comment\n  This is a block comment\n", 1]]

    tests['Call'] = ->
        lex "->", [['CALL', '->', 1]]
        lex "=>", [['CALL', '=>', 1]]
    
    tests['Symbols'] = ->
        for char in ",@=.[](){}?"
            lex char, [[char, char, 1]]

        lex ';', [['TERMINATOR', ';', 1]]
    
    tests['Shift'] = ->
        lex "<<", [['SHIFT','<<',1]]
        lex ">>", [['SHIFT','>>',1]]
        lex ">>>", [['SHIFT','>>>',1]]

    tests['Compare'] = ->
        lex "<", [['COMPARE','<',1]]
        lex "<=", [['COMPARE','<=',1]]
        lex ">", [['COMPARE','>',1]]
        lex ">=", [['COMPARE','>=',1]]
        # TODO: What to do with singular '!'?
        lex "!=", [['COMPARE', '!=', 1]]
    


    ###
      Compound tests
    ###
    
    ###
      Test runner
    ###
    now = Date.now()
    passed = true
    count = 0
    for name, fn of tests
        try
            fn()
        catch err
            console.log "#{red}FAIL#{reset} #{bold}#{name}#{reset}: #{err}"
            passed = false
            break
        count++
    if passed
        time = -> ms = -(now - now = Date.now()); fmt ms
        console.log "#{count} tests passed in #{time()}"

# Either run the tests or lex some input if a filename is given as an argument
l = syntaxes["CoffeeScript"]
now = Date.now()
time   = -> ms = -(now - now = Date.now()); fmt ms
if process.argv[2]?
    tokens = l.tokenize(fs.readFileSync(process.argv[2], "UTF-8"), rewrite:off)
else
    test()
    
#time_taken = "Lexing occurred in #{time()}"
#console.log tokens
#console.log time_taken

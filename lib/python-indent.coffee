{CompositeDisposable} = require 'atom'

module.exports = PythonIndent =
  config:
    openingDelimiterIndentRegex:
      type: 'string'
      default: '^.*(\\(|\\[).*,\\s*$'
      description: 'Regular Expression for _aligned with opening delimiter_ continuation indent type, and used for determining when this type of indent should be _started_.'
    openingDelimiterUnindentRegex:
      type: 'string'
      default: '^\\s+\\S*(\\)|\\])\\s*:?\\s*$'
      description: 'Regular Expression for _aligned with opening delimiter_ continuation indent type, and used for determining when this type of indent should be _ended_.'
    hangingIndentRegex:
      type: 'string'
      default: '^.*(\\(|\\[)\\s*$'
      description: 'Regular Expression for _hanging indent_ used for determining when this type of indent should be _started_.'
    hangingIndentTabs:
      type: 'number'
      default: 1
      description: 'Number of tabs used for _hanging_ indents'
      enum: [
        1,
        2
      ]

  activate: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-text-editor', 'editor:newline': => @properlyIndent(event)

    # Cache settings
    @openingDelimiterIndentRegex = new RegExp(atom.config.get 'python-indent.openingDelimiterIndentRegex')
    @openingDelimiterUnindentRegex = new RegExp(atom.config.get 'python-indent.openingDelimiterUnindentRegex')
    @hangingIndentRegex = new RegExp(atom.config.get 'python-indent.hangingIndentRegex')

  deactivate: ->
    @subscriptions.dispose()

  properlyIndent: (e) ->
    # Make sure this is a Python file
    editor = atom.workspace.getActiveTextEditor()
    return unless editor.getGrammar().scopeName.substring(0, 13) == 'source.python'

    # Get base variables
    row = editor.getCursorBufferPosition().row
    col = editor.getCursorBufferPosition().column

    # What does this line do?
    return unless row

    PythonIndent.indentCorrectly(editor, row, col)


  indentCorrectly: (editor, row, col) ->
    # Parse the entire file up to the current point, keeping track of brackets
    lines = editor.getTextInBufferRange([[0,0], [row, col]]).split('\n')

    bracketStack = PythonIndent.parseLines(lines)

    if not bracketStack.length
        return


    # this is the column where the bracket was, so need to bump by one
    indentColumn = bracketStack.pop()[1] + 1

    # Get tab length for context
    tabLength = editor.getTabLength()

    console.log('indentColumn: ', indentColumn)

    # Calculate soft-tabs from spaces (can have remainder)
    tabs = (indentColumn / tabLength)
    rem = ((tabs - Math.floor(tabs)) * tabLength)
    console.log('tabs: ', tabs, 'rem: ', rem)

    # If there's a remainder, `editor.buildIndentString` requires the tab to
    # be set past the desired indentation level, thus the ceiling.
    tabs = if rem > 0 then Math.ceil tabs else tabs

    # Offset is the number of spaces to subtract from the soft-tabs if they
    # are past the desired indentation (not divisible by tab length).
    offset = if rem > 0 then tabLength - rem else 0

    # I'm glad Atom has an optional `column` param to subtract spaces from
    # soft-tabs, though I don't see it used anywhere in the core.

    console.log('tabs:', tabs, 'offset:', offset)

    indent = editor.buildIndentString(tabs, column=offset)

    console.log('len:', indent.length, 'str: "', indent, '"')

    # Set the indent
    editor.getBuffer().setTextInRange([[row, 0], [row, editor.indentationForBufferRow(row) * tabLength]], indent)


  parseLines: (lines) ->
    # bracketStack is a stack of [row, column] arrays indicating the
    # location of the opening bracket (square, curly, or parentheses)
    bracketStack = []
    # if we are in a string, this tells us what character introduced the string
    # i.e., did this string start with ' or with "?
    stringDelimiter = []

    # loop over each line, adding to each stack
    for row in [0 .. lines.length-1]
        line = lines[row]

        # boolean, whether or not the current character is being escaped
        isEscaped = false

        for col in [0 .. line.length-1]
            c = line[col]

            # if stringDelimiter is set, then we are in a string
            if stringDelimiter.length
                # we are currently in a string
                if isEscaped
                    isEscaped = false
                else
                    switch c
                        when stringDelimiter
                            stringDelimiter = []
                        when '\\'
                            isEscaped = true
            else
                if c == '#'
                    break
                if c in '[({'
                    bracketStack.push([row, col])
                if c in '})]'
                    bracketStack.pop()
                if c in '\'"'
                    stringDelimiter = c

    # return the stacks as an array
    return bracketStack

# A standalone PowerShell profile built from Chris Titus Tech's utilities, without the GitHub auto-update.
# Source code: https://github.com/ChrisTitusTech/powershell-profile/blob/main/Microsoft.PowerShell_profile.ps1
# Copy it to $PROFILE.CurrentUserCurrentHost (usually C:\Users\<you>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1).
# It does not depend on any other file.
#
# Each function has an approved Verb-Noun name, with the short command kept as an alias.

using namespace System.Management.Automation
using namespace System.Management.Automation.Language

#region Environment checks

# Test-InteractiveShell: $true when the console is not redirected.
function Test-InteractiveShell {
    try {
        return $Host.Name -eq 'ConsoleHost' -and
            -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected
    } catch {
        return $false
    }
}

# Test-Command: $true if a command, function or alias with this name exists.
function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

# Get-UriContent: downloads a URL and returns its text. Used by Get-PublicIP.
function Get-UriContent {
    param([Parameter(Mandatory)][string]$Uri)

    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadString($Uri)
    } finally {
        $client.Dispose()
    }
}

function Get-ProfileDir {
    switch ($PSVersionTable.PSEdition) {
        'Core' { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'; break }
        'Desktop' { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell'; break }
        default {
            throw "Unsupported PowerShell edition: $($PSVersionTable.PSEdition)"
        }
    }
}

#endregion Environment checks

$isInteractiveShell = Test-InteractiveShell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$profileDir = Get-ProfileDir #Split-Path -Path $PROFILE.CurrentUserCurrentHost -Parent

# Lines kept in the history file. Used as the default by Optimize-PSReadLineHistory.
$MaximumHistoryCount = 10000

#region Editor

# Resolve-Editor: picks the first installed editor from the list and stores it in $EDITOR.
# Falls back to Notepad.
function Resolve-Editor {
    foreach ($candidate in 'code', 'codium', 'notepad++', 'nvim', 'pvim', 'vim', 'vi', 'sublime_text') {
        if (Test-Command $candidate) {
            return $candidate
        }
    }

    return 'notepad'
}

$EDITOR = Resolve-Editor

# Edit-Profile (alias: ep): opens this profile in the editor.
function Edit-Profile {
    & $EDITOR $PROFILE.CurrentUserCurrentHost
}

#endregion Editor

#region Window title and prompt

# Sets the window title to the PowerShell version, with [ADMIN] when elevated.
if ($isInteractiveShell) {
    try {
        $adminSuffix = if ($isAdmin) { ' [ADMIN]' } else { '' }
        $Host.UI.RawUI.WindowTitle = "PowerShell $($PSVersionTable.PSVersion)$adminSuffix"
    } catch {
        Write-Verbose "Unable to set console title: $_"
    }
}

# Resolve-OhMyPoshTheme: finds the first oh-my-posh theme file that exists.
function Resolve-OhMyPoshTheme {
    $candidates = @(
        $env:POSH_THEME,
        (Join-Path $HOME '.dev-boost.omp.json'),
        (Join-Path $profileDir '.dev-boost.omp.json')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

# Initialize-PromptTool: sets up oh-my-posh (prompt theme) and zoxide (the z command).
function Initialize-PromptTool {
    if (-not $isInteractiveShell) {
        return
    }

    if (Test-Command oh-my-posh) {
        $theme = Resolve-OhMyPoshTheme
        if ($theme) {
            oh-my-posh init pwsh --config $theme | Invoke-Expression
        } else {
            Write-Warning 'Oh My Posh theme not found. Put a theme file in your home folder, or set $env:POSH_THEME.'
        }
    } else {
        Write-Warning 'oh-my-posh is not installed. Install it with: winget install JanDeDobbeleer.OhMyPosh'
    }

    if (Test-Command zoxide) {
        Invoke-Expression (& { (zoxide init --cmd z powershell | Out-String) })
    } else {
        Write-Warning 'zoxide is not installed. Install it with: winget install ajeetdsouza.zoxide'
    }
}

#endregion Window title and prompt

#region PSReadLine (command-line editing, history and prediction)

# Set-PSReadLineOptionsCompat: applies PSReadLine options, dropping the prediction options Windows PowerShell doesn't support.
function Set-PSReadLineOptionsCompat {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable]$Options)

    $safeOptions = $Options.Clone()
    if ($PSVersionTable.PSEdition -ne 'Core') {
        $safeOptions.Remove('PredictionSource')
        $safeOptions.Remove('PredictionViewStyle')
    }

    if ($PSCmdlet.ShouldProcess('PSReadLine', 'Set PSReadLine options')) {
        Set-PSReadLineOption @safeOptions
    }
}

# Set-PredictionSource: turns on history-based prediction (PowerShell 7 only) and sets the history limit.
function Set-PredictionSource {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess('PSReadLine', 'Set prediction source')) {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        }

        Set-PSReadLineOption -MaximumHistoryCount 10000
    }
}

# Initialize-PSReadLine: sets the editing mode, colours, history and key bindings.
function Initialize-PSReadLine {
    if (-not $isInteractiveShell -or -not (Get-Module -ListAvailable -Name PSReadLine)) {
        return
    }

    $options = @{
        EditMode                      = 'Windows'
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        PredictionSource              = 'History'
        PredictionViewStyle           = 'ListView' # F2 toggles InlineView/ListView
        BellStyle                     = 'None'
        ShowToolTips                  = $true
        Colors                        = @{
            Command   = '#87CEEB'
            Parameter = '#98FB98'
            Operator  = '#FFB6C1'
            Variable  = '#DDA0DD'
            String    = '#FFDAB9'
            Number    = '#B0E0E6'
            Type      = '#F0E68C'
            Comment   = '#D3D3D3'
            Keyword   = '#8367c7'
            Error     = '#FF6347'
        }
    }

    Set-PSReadLineOptionsCompat -Options $options
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
    Set-PSReadLineKeyHandler -Chord 'Ctrl+w' -Function BackwardDeleteWord
    Set-PSReadLineKeyHandler -Chord 'Alt+d' -Function DeleteWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
    Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

    # This is an example of a macro that you might use to execute a command.
    # This will add the command to history.
    Set-PSReadLineKeyHandler -Key Ctrl+b `
        -BriefDescription BuildCurrentDirectory `
        -LongDescription "Build the current directory" `
        -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("MSBuild /t:Rebuild")
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }

    #region Smart Insert/Delete

    # The next four key handlers are designed to make entering matched quotes
    # parens, and braces a nicer experience.  I'd like to include functions
    # in the module that do this, but this implementation still isn't as smart
    # as ReSharper, so I'm just providing it as a sample.

    Set-PSReadLineKeyHandler -Key '"', "'" `
        -BriefDescription SmartInsertQuote `
        -LongDescription "Insert paired quotes if not already on a quote" `
        -ScriptBlock {
        param($key, $arg)

        $quote = $key.KeyChar

        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        # If text is selected, just quote it without any smarts
        if ($selectionStart -ne -1) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
            return
        }

        $ast = $null
        $tokens = $null
        $parseErrors = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

        function FindToken {
            param($tokens, $cursor)

            foreach ($token in $tokens) {
                if ($cursor -lt $token.Extent.StartOffset) { continue }
                if ($cursor -lt $token.Extent.EndOffset) {
                    $result = $token
                    $token = $token -as [StringExpandableToken]
                    if ($token) {
                        $nested = FindToken $token.NestedTokens $cursor
                        if ($nested) { $result = $nested }
                    }

                    return $result
                }
            }
            return $null
        }

        $token = FindToken $tokens $cursor

        # If we're on or inside a **quoted** string token (so not generic), we need to be smarter
        if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
            # If we're at the start of the string, assume we're inserting a new string
            if ($token.Extent.StartOffset -eq $cursor) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                return
            }

            # If we're at the end of the string, move over the closing quote if present.
            if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                return
            }
        }

        if ($null -eq $token -or
            $token.Kind -eq [TokenKind]::RParen -or $token.Kind -eq [TokenKind]::RCurly -or $token.Kind -eq [TokenKind]::RBracket) {
            if ($line[0..$cursor].Where{ $_ -eq $quote }.Count % 2 -eq 1) {
                # Odd number of quotes before the cursor, insert a single quote
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
            }
            else {
                # Insert matching quotes, move cursor to be in between the quotes
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            }
            return
        }

        # If cursor is at the start of a token, enclose it in quotes.
        if ($token.Extent.StartOffset -eq $cursor) {
            if ($token.Kind -eq [TokenKind]::Generic -or $token.Kind -eq [TokenKind]::Identifier -or 
                $token.Kind -eq [TokenKind]::Variable -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
                $end = $token.Extent.EndOffset
                $len = $end - $cursor
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
                return
            }
        }

        # We failed to be smart, so just insert a single quote
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
    }

    Set-PSReadLineKeyHandler -Key '(', '{', '[' `
        -BriefDescription InsertPairedBraces `
        -LongDescription "Insert matching braces" `
        -ScriptBlock {
        param($key, $arg)

        $closeChar = switch ($key.KeyChar) {
            <#case#> '(' { [char]')'; break }
            <#case#> '{' { [char]'}'; break }
            <#case#> '[' { [char]']'; break }
        }

        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        
        if ($selectionStart -ne -1) {
            # Text is selected, wrap it in brackets
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        }
        else {
            # No text is selected, insert a pair
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
    }

    Set-PSReadLineKeyHandler -Key ')', ']', '}' `
        -BriefDescription SmartCloseBraces `
        -LongDescription "Insert closing brace or skip" `
        -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($line[$cursor] -eq $key.KeyChar) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
        }
    }

    Set-PSReadLineKeyHandler -Key Backspace `
        -BriefDescription SmartBackspace `
        -LongDescription "Delete previous character or matching quotes/parens/braces" `
        -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -gt 0) {
            $toMatch = $null
            if ($cursor -lt $line.Length) {
                switch ($line[$cursor]) {
                    <#case#> '"' { $toMatch = '"'; break }
                    <#case#> "'" { $toMatch = "'"; break }
                    <#case#> ')' { $toMatch = '('; break }
                    <#case#> ']' { $toMatch = '['; break }
                    <#case#> '}' { $toMatch = '{'; break }
                }
            }

            if ($toMatch -ne $null -and $line[$cursor - 1] -eq $toMatch) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
            }
            else {
                [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
            }
        }
    }

    #endregion Smart Insert/Delete

    #region Additional key bindings

    # Sometimes you enter a command but realize you forgot to do something else first.
    # This binding will let you save that command in the history so you can recall it,
    # but it doesn't actually execute.  It also clears the line with RevertLine so the
    # undo stack is reset - though redo will still reconstruct the command line.
    Set-PSReadLineKeyHandler -Chord 'Alt+w' `
        -BriefDescription SaveInHistory `
        -LongDescription "Save current line in history but do not execute" `
        -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    }

    # Insert text from the clipboard as a here string
    Set-PSReadLineKeyHandler -Chord 'Ctrl+v' `
        -BriefDescription PasteAsHereString `
        -LongDescription "Paste the clipboard text as a here string" `
        -ScriptBlock {
        param($key, $arg)

        # Get-Clipboard is built in; no WPF assembly needed.
        $text = Get-Clipboard -Raw
        if ($text) {
            # Remove trailing spaces, convert \r\n to \n, and trim the final newline.
            $text = ($text -replace "\p{Zs}*`r?`n", "`n").TrimEnd()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n$text`n'@")
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Ding()
        }
    }

    # Sometimes you want to get a property of invoke a member on what you've entered so far
    # but you need parens to do that.  This binding will help by putting parens around the current selection,
    # or if nothing is selected, the whole line.
    Set-PSReadLineKeyHandler -Chord 'Alt+(' `
        -BriefDescription ParenthesizeSelection `
        -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
        -ScriptBlock {
        param($key, $arg)

        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($selectionStart -ne -1) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
        }
    }

    # Each time you press Alt+', this key handler will change the token
    # under or before the cursor.  It will cycle through single quotes, double quotes, or
    # no quotes each time it is invoked.
    Set-PSReadLineKeyHandler -Chord "Alt+'" `
        -BriefDescription ToggleQuoteArgument `
        -LongDescription "Toggle quotes on the argument under the cursor" `
        -ScriptBlock {
        param($key, $arg)

        $ast = $null
        $tokens = $null
        $errors = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

        $tokenToChange = $null
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $extent = $tokens[$i].Extent
            if ($extent.StartOffset -le $cursor -and $extent.EndOffset -ge $cursor) {
                $tokenToChange = $tokens[$i]

                # If the cursor is just past the previous token, prefer the token starting at the cursor.
                if ($extent.EndOffset -eq $cursor -and ($i + 1) -lt $tokens.Count) {
                    $nextToken = $tokens[$i + 1]
                    if ($nextToken.Extent.StartOffset -eq $cursor) {
                        $tokenToChange = $nextToken
                    }
                }
                break
            }
        }

        if ($tokenToChange -ne $null) {
            $extent = $tokenToChange.Extent
            $tokenText = $extent.Text
            if ($tokenText[0] -eq '"' -and $tokenText[-1] -eq '"') {
                # Switch to no quotes
                $replacement = $tokenText.Substring(1, $tokenText.Length - 2)
            }
            elseif ($tokenText[0] -eq "'" -and $tokenText[-1] -eq "'") {
                # Switch to double quotes
                $replacement = '"' + $tokenText.Substring(1, $tokenText.Length - 2) + '"'
            }
            else {
                # Add single quotes
                $replacement = "'" + $tokenText + "'"
            }

            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                $extent.StartOffset,
                $tokenText.Length,
                $replacement)
        }
    }

    # This example will replace any aliases on the command line with the resolved commands.
    Set-PSReadLineKeyHandler -Chord "Alt+%" `
        -BriefDescription ExpandAliases `
        -LongDescription "Replace all aliases with the full command" `
        -ScriptBlock {
        param($key, $arg)

        $ast = $null
        $tokens = $null
        $errors = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

        $startAdjustment = 0
        foreach ($token in $tokens) {
            if ($token.TokenFlags -band [TokenFlags]::CommandName) {
                $alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')
                if ($alias -ne $null) {
                    $resolvedCommand = $alias.ResolvedCommandName
                    if ($resolvedCommand -ne $null) {
                        $extent = $token.Extent
                        $length = $extent.EndOffset - $extent.StartOffset
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                            $extent.StartOffset + $startAdjustment,
                            $length,
                            $resolvedCommand)

                        # Our copy of the tokens won't have been updated, so we need to
                        # adjust by the difference in length
                        $startAdjustment += ($resolvedCommand.Length - $length)
                    }
                }
            }
        }
    }

    # F1 for help on the command line - naturally
    Set-PSReadLineKeyHandler -Key F1 `
        -BriefDescription CommandHelp `
        -LongDescription "Open the help window for the current command" `
        -ScriptBlock {
        param($key, $arg)

        $ast = $null
        $tokens = $null
        $errors = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

        $commandAst = $ast.FindAll( {
                $node = $args[0]
                $node -is [CommandAst] -and
                $node.Extent.StartOffset -le $cursor -and
                $node.Extent.EndOffset -ge $cursor
            }, $true) | Select-Object -Last 1

        if ($commandAst -ne $null) {
            $commandName = $commandAst.GetCommandName()
            if ($commandName -ne $null) {
                $command = $ExecutionContext.InvokeCommand.GetCommand($commandName, 'All')
                if ($command -is [AliasInfo]) {
                    $commandName = $command.ResolvedCommandName
                }

                if ($commandName -ne $null) {
                    Get-Help $commandName -ShowWindow
                }
            }
        }
    }

    # `ForwardChar` accepts the entire suggestion text when the cursor is at the end of the line.
    # This custom binding makes `RightArrow` behave similarly - accepting the next word instead of the entire suggestion text.
    Set-PSReadLineKeyHandler -Key RightArrow `
        -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
        -LongDescription "Move cursor one character to the right in the current editing line and accept the next word in suggestion when it's at the end of current editing line" `
        -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
        }
    }

    #endregion Additional key bindings

    # Lines containing these words are kept out of the history file.
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$Line)
        -not ($Line -match 'password|passwd|pwd=|secret|token|sonar\.login|login=|authorization|apikey|ghp_|ConvertTo-SecureString|-Credential')
    }

    Set-PredictionSource
}

# https://gist.github.com/jdhitsolutions/841fcd6f0318f9f51d2e05873ba658a4#file-optimize-psreadlinehistory
# Builds the comparison key for a history entry. Drive-and-path tokens (D:\Dev, d:/dev\)
# are compared case-insensitively with slashes normalised and trailing separators removed,
# so D:\Development, D:\Development\ and d:\development all count as the same entry.
function Get-DedupeKey {
    param([string]$Entry)

    $pathPattern = '[A-Za-z]:[\\/][^\s"''`;|>]*'
    $sb = [System.Text.StringBuilder]::new()
    $last = 0
    foreach ($m in [regex]::Matches($Entry, $pathPattern)) {
        [void]$sb.Append($Entry.Substring($last, $m.Index - $last))
        [void]$sb.Append($m.Value.Replace('/', '\').TrimEnd('\').ToLowerInvariant())
        $last = $m.Index + $m.Length
    }
    [void]$sb.Append($Entry.Substring($last))
    $sb.ToString()
}

Function Optimize-PSReadLineHistory {
    <#
    .SYNOPSIS
        Optimize the PSReadline history file
    .DESCRIPTION
        The PSReadline module can maintain a persistent command-line history. However, there are no provisions for managing the file. When the file gets very large, performance starting PowerShell can be affected. This command will trim the history file to a specified length as well as removing any duplicate entries.
    .PARAMETER MaximumLineCount
    Set the maximum number of lines to store in the history file.
    .PARAMETER Passthru
    By default this command does not write anything to the pipeline. Use -Passthru to get the updated history file.
    .EXAMPLE
        PS C:\> Optimize-PSReadelineHistory
        
        Trim the PSReadlineHistory file to default maximum number of lines.
    .EXAMPLE
        PS C:\> Optimize-PSReadelineHistory -maximumlinecount 500 -passthru

            Directory: C:\Users\Jeff\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline


            Mode                LastWriteTime         Length Name
            ----                -------------         ------ ----
            -a----        11/2/2017   8:21 AM           1171 ConsoleHost_history.txt
                    
        Trim the PSReadlineHistory file to 500 lines and display the file listing.
    .INPUTS
        None
    .OUTPUTS
       None
    .NOTES
        version 1.0
        Learn more about PowerShell: http://jdhitsolutions.com/blog/essential-powershell-resources/
    .LINK
    Get-PSReadlineOption
    .LINK
    Set-PSReadlineOption
    #>
    [cmdletbinding(SupportsShouldProcess)]
    Param(
        [Parameter(ValueFromPipeline)]
        [int32]$MaximumLineCount = $MaximumHistoryCount,
        [switch]$Passthru
    )
    Begin {
        Write-Verbose "[$((Get-Date).TimeofDay) BEGIN  ] Starting $($myinvocation.mycommand)"
        $History = (Get-PSReadlineOption).HistorySavePath
    } #begin

    Process {
        if (Test-Path -path $History) {
            Write-Verbose "[$((Get-Date).TimeofDay) PROCESS] Measuring $history"
            $myHistory = Get-Content -Path $History
    
            Write-Verbose "[$((Get-Date).TimeofDay) PROCESS] Found $($myHistory.count) lines of history"
            # Group continuation lines (ending in a backtick) into one entry, as the F7 handler does,
            # so multi-line commands are never split apart.
            $entries = [System.Collections.Generic.List[string]]::new()
            $pending = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $myHistory) {
                $pending.Add($line)
                if (-not $line.EndsWith('`')) {
                    $entries.Add(($pending -join "`n"))
                    $pending.Clear()
                }
            }
            if ($pending.Count -gt 0) { $entries.Add(($pending -join "`n")) }

            # Keep the most recent copy of each entry, in original order, then apply the cap.
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            $keep = @(for ($i = $entries.Count - 1; $i -ge 0; $i--) {
                if ($seen.Add((Get-DedupeKey $entries[$i]))) { $entries[$i] }
            })
            [array]::Reverse($keep)
            $keep = @($keep | Select-Object -Last $MaximumLineCount)

            $changed = $keep.Count -ne $entries.Count
            
            if ($changed) {
                Write-Verbose "[$((Get-Date).TimeofDay) PROCESS] Rewriting history: $($entries.Count) entries -> $($keep.Count)"
                if ($PSCmdlet.ShouldProcess($History, "Remove duplicate entries and trim to $MaximumLineCount")) {
                    $keep | ForEach-Object { $_ -split "`n" } | Set-Content -Path $History
                }
            }
            else {
                Write-Verbose "[$((Get-Date).TimeofDay) PROCESS] No duplicates found; history is clean."
            }
        }
        else {
            Write-Warning "Failed to find $history"
        }

    } #process

    End {
        If ($Passthru) {
            Get-Item -Path $History
        }
        Write-Verbose "[$((Get-Date).TimeofDay) END    ] Ending $($myinvocation.mycommand)"
    } #end 

} #close Name

#endregion PSReadLine (command-line editing, history and prediction)

#region Tab completion

# Register-CustomCompletion: tab completion for common git, npm and deno subcommands, and the dotnet CLI.
function Register-CustomCompletion {
    if (-not $isInteractiveShell) {
        return
    }

    $completionMap = @{
        git  = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout')
        npm  = @('install', 'start', 'run', 'test', 'build')
        deno = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'info', 'doc', 'upgrade')
    }

    Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $null = $cursorPosition
        $completionWord = $wordToComplete
        $map = $completionMap
        $command = $commandAst.CommandElements[0].Value
        if ($map.ContainsKey($command)) {
            $map[$command] |
                Where-Object { $_ -like "$completionWord*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
    }.GetNewClosure()

    if (Test-Command dotnet) {
        Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            $null = $wordToComplete
            dotnet complete --position $cursorPosition $commandAst.ToString() |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
    }
}

#endregion Tab completion

#region Session and window

# Start-AdminShell (alias: su): opens a new elevated shell in the current folder, or runs the given command in it.
# Example: su   or   su choco upgrade all
function Start-AdminShell {
    $cwd = (Get-Location).ProviderPath
    $shell = if (Test-Command pwsh) { 'pwsh.exe' } else { 'powershell.exe' }
    $shellArgs = if ($args.Count -gt 0) { @('-NoExit', '-Command', ($args -join ' ')) } else { @('-NoExit') }

    if (Test-Command wt) {
        Start-Process wt -Verb RunAs -ArgumentList (@('-d', $cwd, $shell) + $shellArgs)
    } else {
        Start-Process $shell -Verb RunAs -WorkingDirectory $cwd -ArgumentList $shellArgs
    }
}

# Update-PowerShell: checks the latest PowerShell release on GitHub and upgrades with winget if you're behind.
function Update-PowerShell {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Test-Command winget)) {
        Write-Warning 'winget is required to update PowerShell automatically.'
        return
    }

    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -ErrorAction Stop
        $currentVersion = [version]$PSVersionTable.PSVersion
        $latestVersion = [version]($release.tag_name -replace '^v', '')

        if ($currentVersion -ge $latestVersion) {
            Write-Host "PowerShell $currentVersion is up to date." -ForegroundColor Green
            return
        }

        if ($PSCmdlet.ShouldProcess("PowerShell $currentVersion", "Upgrade to $latestVersion")) {
            winget upgrade --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) {
                Write-Error "winget failed to update PowerShell. Exit code: $LASTEXITCODE"
                return
            }
            Write-Host 'PowerShell has been updated. Restart your shell to use the new version.' -ForegroundColor Magenta
        }
    } catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}

# Get-SystemUptime (alias: uptime): shows how long the computer has been running.
function Get-SystemUptime {
    $boot = if (Get-Command Get-Uptime -ErrorAction SilentlyContinue) {
        Get-Uptime -Since
    } else {
        (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    }

    (Get-Date) - $boot | Select-Object Days, Hours, Minutes, Seconds
}

# Get-SystemInfo (alias: sysinfo): shows detailed computer information.
function Get-SystemInfo { Get-ComputerInfo }

# Clear-DnsCache (alias: flushdns): clears the DNS resolver cache.
function Clear-DnsCache {
    Clear-DnsClientCache
    Write-Host 'DNS has been flushed'
}

# Clear-Cache: deletes temporary files and the Prefetch and INetCache folders. Supports -WhatIf.
function Clear-Cache {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $paths = @(
        "$env:SystemRoot\Prefetch\*",
        "$env:SystemRoot\Temp\*",
        "$env:TEMP\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"
    )

    foreach ($path in $paths) {
        if ($PSCmdlet.ShouldProcess($path, 'Remove cached files')) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Get-PublicIP (alias: pubip): prints your public IP address (uses ifconfig.me).
function Get-PublicIP {
    (Get-UriContent -Uri 'https://ifconfig.me/ip').Trim()
}

# Copy-ClipboardText (alias: cpy): copies the text to the clipboard. Example: cpy hello world
function Copy-ClipboardText { Set-Clipboard ($args -join ' ') }

# Get-ClipboardText (alias: pst): prints the clipboard text.
function Get-ClipboardText { Get-Clipboard }

# Reloads PATH in the current session from the Machine and User values in the registry.
# Use it after installing a tool so the new PATH entries work without a restart.
function Update-EnvPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") +
    ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")
}

#endregion Session and window

#region Files and folders

# Set-FileTimestamp (alias: touch): creates an empty file, or updates the timestamp if it exists.
function Set-FileTimestamp {
    param([Parameter(Mandatory)][string]$File)

    if (Test-Path -Path $File) {
        (Get-Item -Path $File).LastWriteTime = Get-Date
    } else {
        New-Item -Path $File -ItemType File -Force | Out-Null
    }
}

# New-File (alias: nf): creates a new file in the current folder.
function New-File {
    param([Parameter(Mandatory)][string]$Name)
    New-Item -ItemType File -Path . -Name $Name -Force | Out-Null
}

# New-DirectoryAndEnter (alias: mkcd): creates a folder (and any missing parents) and moves into it.
function New-DirectoryAndEnter {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Set-Location -Path $Path
}

# Find-FileByName (alias: ff): finds files and folders whose name contains the text, searching recursively.
function Find-FileByName {
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
}

# Expand-ZipHere (alias: unzip): extracts a zip into the current folder.
function Expand-ZipHere {
    param([Parameter(Mandatory)][string]$File)

    if (-not (Test-Path -Path $File -PathType Leaf)) {
        Write-Error "File not found: $File"
        return
    }

    Expand-Archive -Path $File -DestinationPath (Get-Location) -Force
}

# Expand-ZipToFolder (alias: unzipto): extracts a zip into a folder.
# Without -Destination, creates a folder named after the zip (without .zip) in the current folder.
# Example: unzipto C:\Downloads\tools.zip   or   unzipto tools.zip D:\Tools
function Expand-ZipToFolder {
    param(
        [Parameter(Mandatory)][string]$File,
        [string]$Destination
    )

    if (-not (Test-Path -Path $File -PathType Leaf)) {
        Write-Error "File not found: $File"
        return
    }

    $zip = Get-Item -LiteralPath $File
    if (-not $Destination) {
        $Destination = Join-Path (Get-Location) $zip.BaseName
    }

    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $Destination -Force
    Write-Host "Extracted '$($zip.Name)' to '$Destination'" -ForegroundColor Green
}

# Remove-ToRecycleBin (alias: trash): sends a file or folder to the Recycle Bin instead of deleting it.
function Remove-ToRecycleBin {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        Write-Error "Item not found: $Path"
        return
    }

    $fullPath = $resolvedPath.ProviderPath
    $item = Get-Item -LiteralPath $fullPath
    $parentPath = if ($item.PSIsContainer) {
        if ($item.Parent) { $item.Parent.FullName } else { Split-Path -Path $item.FullName -Parent }
    } else {
        $item.DirectoryName
    }

    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        Write-Error "Cannot move root path to Recycle Bin: $fullPath"
        return
    }

    $shell = New-Object -ComObject 'Shell.Application'
    $shellFolder = $shell.NameSpace($parentPath)
    $shellItem = if ($shellFolder) { $shellFolder.ParseName($item.Name) } else { $null }

    if ($shellItem) {
        $shellItem.InvokeVerb('delete')
    } else {
        Write-Error "Could not move item to Recycle Bin: $fullPath"
    }
}

# Set-LocationDocuments (alias: docs) and Set-LocationDesktop (alias: dtop) and Set-LocationDownloads (alias: dl): jump to Documents or Desktop or Downloads.
function Set-LocationDocuments { Set-Location -Path ([Environment]::GetFolderPath('MyDocuments')) }

function Set-LocationDesktop { Set-Location -Path ([Environment]::GetFolderPath('Desktop')) }

function Set-LocationDownloads { Set-Location -Path (Join-Path $HOME 'Downloads') }

# Get-ChildItemTable (alias: la): lists visible files in a table.
function Get-ChildItemTable { Get-ChildItem | Format-Table -AutoSize }

# Get-ChildItemAll (alias: ll): lists all files, including hidden ones, in a table.
function Get-ChildItemAll { Get-ChildItem -Force | Format-Table -AutoSize }

# Get-VolumeInfo (alias: df): shows drive and volume information.
function Get-VolumeInfo { Get-Volume }

# Import-TerminalIcons: loads the Terminal-Icons module if installed, or warns the user how to install it.
function Import-TerminalIcons {
    # Already loaded in this session
    if (Get-Module -Name Terminal-Icons) { return }

    # Not installed: tell the user how to install it
    if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
        Write-Warning 'Terminal-Icons is not installed. Install it with: Install-PSResource Terminal-Icons -Scope CurrentUser'
        return
    }

    try {
        Import-Module -Name Terminal-Icons -ErrorAction Stop
    } catch {
        Write-Warning "Could not load Terminal-Icons: $_"
    }
}

# Move-Up (alias: up): moves up one folder by default, or several with -Levels. Example: up 3
function Move-Up {
    param([ValidateRange(1, 100)][int]$Levels = 1)   # Number of folders to go up (1 to 100).
    Set-Location ('..\' * $Levels)
}

# Base64-encodes UTF-8 text. Takes input from -Text, the pipeline, or the clipboard when empty.
# Example: Encode-Base64 'hello'
function Encode-Base64 {
    param(
        [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$Text
    )
    process {
        if (-not $Text) { $Text = Get-Clipboard -Raw }
        [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
    }
}

function Test-FileChecksum {
    <#
    .SYNOPSIS
        Computes a file's checksum, optionally verifying it against a value or a checksum file.
    .EXAMPLE
        Test-FileChecksum .\a.iso
    .EXAMPLE
        Test-FileChecksum .\a.iso -Algorithm SHA512 -Checksum 'abc123...'
    .EXAMPLE
        Test-FileChecksum .\a.iso -ChecksumFile .\a.iso.sha256
    #>
    [CmdletBinding(DefaultParameterSetName = 'Compute')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA384', 'SHA512')]
        [string]$Algorithm = 'SHA256',

        [Parameter(ParameterSetName = 'Value', Mandatory)]
        [string]$Checksum,

        [Parameter(ParameterSetName = 'File', Mandatory)]
        [string]$ChecksumFile
    )

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $actual = (Get-FileHash -LiteralPath $item.FullName -Algorithm $Algorithm).Hash

    if ($PSCmdlet.ParameterSetName -eq 'Compute') {
        return [pscustomobject]@{ File = $item.Name; Algorithm = $Algorithm; Hash = $actual }
    }

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $lines = Get-Content -LiteralPath $ChecksumFile -ErrorAction Stop |
            Where-Object { $_.Trim() }
        # Prefer the line naming this file (sha256sum style), else use the first line
        $line = $lines | Where-Object { $_ -like "*$($item.Name)*" } | Select-Object -First 1
        if (-not $line) { $line = $lines | Select-Object -First 1 }
        $Checksum = ($line.Trim() -split '\s+')[0]
    }

    $expected = $Checksum.Trim() -replace '\s', ''
    $match = $actual -ieq $expected

    Write-Host "Algorithm : $Algorithm"
    Write-Host "Expected  : $expected"
    Write-Host "Actual    : $actual"
    if ($match) { Write-Host 'Result    : MATCH' -ForegroundColor Green }
    else        { Write-Host 'Result    : MISMATCH' -ForegroundColor Red }

    return $match
}

function New-ApiKey {
    param(
        [int]$Bytes = 32   # 32 bytes = 64 hex characters
    )

    $buffer = New-Object byte[] $Bytes
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }

    -join ($buffer | ForEach-Object { '{0:x2}' -f $_ })
}

#endregion Files and folders

#region Development

# cleanup.ps1 - Recursively delete bin, obj, and node_modules folders
# Usage: Invoke-Cleanup [directory]
# If no directory is provided, uses current directory
function Invoke-Cleanup {
    param(
        [string]$TargetDir = "."
    )

    $TargetDir = Resolve-Path $TargetDir

    if (-not (Test-Path $TargetDir -PathType Container)) {
        Write-Host "Error: '$TargetDir' is not a valid directory." -ForegroundColor Red
        return
    }

    $FolderNames = @("bin", "obj", "node_modules", "packages")

    Write-Host "Scanning: $TargetDir" -ForegroundColor Cyan
    Write-Host "Will delete: $($FolderNames -join ', ')" -ForegroundColor Cyan
    Write-Host ""

    # Manually traverse directories, pruning matched folders so we don't recurse into them
    function Find-TargetFolders {
        param([string]$Path)

        $results = @()
        try {
            $children = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
        } catch { return $results }

        foreach ($child in $children) {
            if ($FolderNames -contains $child.Name) {
                # Found a match — add it, do NOT recurse into it
                $results += $child
            } else {
                # Not a match — recurse deeper
                $results += Find-TargetFolders -Path $child.FullName
            }
        }
        return $results
    }

    $Found = Find-TargetFolders -Path $TargetDir

    if ($Found.Count -eq 0) {
        Write-Host "Nothing to clean up - no matching folders found." -ForegroundColor Green
        return
    }

    # Show what will be deleted with sizes
    Write-Host "Found the following folders:" -ForegroundColor Yellow
    foreach ($dir in $Found) {
        $size = (Get-ChildItem $dir.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeMB = if ($size -gt 1MB) { "{0:N1} MB" -f ($size / 1MB) } elseif ($size -gt 1KB) { "{0:N1} KB" -f ($size / 1KB) } else { "$size B" }
        Write-Host "  $($dir.FullName) ($sizeMB)" -ForegroundColor Gray
    }

    Write-Host ""
    $confirm = Read-Host "Proceed with deletion? [y/N]"

    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Aborted. Nothing was deleted." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Deleting..." -ForegroundColor Cyan

    $deleted = 0
    $errors = 0

    foreach ($dir in $Found) {
        try {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
            Write-Host "  Deleted: $($dir.FullName)" -ForegroundColor Green
            $deleted++
        } catch {
            Write-Host "  Failed:  $($dir.FullName) - $_" -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ""
    Write-Host "Done. Deleted: $deleted  |  Errors: $errors" -ForegroundColor Cyan
}

#endregion Development

#region WinGet wrappers. @args passes extra arguments through to winget unchanged.

# Update-WinGetPackage (alias: wup): lists or applies upgrades. Example: wup --all
function Update-WinGetPackage { winget upgrade @args }

# Search-WinGetPackage (alias: wsr): searches the repository. Example: wsr vscode
function Search-WinGetPackage { winget search @args }

# Install-WinGetPackage (alias: wi): installs a package. Example: wi Git.Git
function Install-WinGetPackage { winget install @args }

# Uninstall-WinGetPackage (alias: wun): uninstalls a package. Example: wun Git.Git
function Uninstall-WinGetPackage { winget uninstall @args }

#endregion

#region Unix-style text and process tools

# Search-Text (alias: grep): searches files recursively under a path, or filters piped input.
# Example: grep TODO .\src   or   Get-Content log.txt | grep error
function Search-Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Pattern,
        [Parameter(Position = 1)][string]$Path,
        [Parameter(ValueFromPipeline)][object]$InputObject
    )

    begin {
        $pipelineInput = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            $pipelineInput.Add($InputObject)
        }
    }

    end {
        if ($Path) {
            Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Select-String -Pattern $Pattern
        } elseif ($pipelineInput.Count -gt 0) {
            $pipelineInput | Select-String -Pattern $Pattern
        } else {
            Write-Error 'Usage: grep <pattern> [path] or pipe input to grep'
        }
    }
}

# Update-FileText (alias: sed): replaces every occurrence of text in a file, in place.
# Example: sed config.json "old" "new"
function Update-FileText {
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Find,
        [Parameter(Mandatory)][string]$Replace
    )

    (Get-Content -Path $File).Replace($Find, $Replace) | Set-Content -Path $File
}

# Get-FileHead (alias: head): first lines of a file.
function Get-FileHead {
    param([Parameter(Mandatory)][string]$Path, [int]$n = 10)
    Get-Content -Path $Path -Head $n
}

# Get-FileTail (alias: tail): last lines of a file. -f keeps watching for new lines.
function Get-FileTail {
    param([Parameter(Mandatory)][string]$Path, [int]$n = 10, [switch]$f)
    Get-Content -Path $Path -Tail $n -Wait:$f
}

# Get-CommandSource (alias: which): shows where a command comes from.
function Get-CommandSource {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command -Name $Name | Select-Object -ExpandProperty Definition
}

# Set-EnvVariable (alias: export): sets an environment variable for the current session.
function Set-EnvVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    Set-Item -Path "env:$Name" -Value $Value -Force
}

# Get-ProcessByName (alias: pgrep): lists processes with that name.
function Get-ProcessByName {
    param([Parameter(Mandatory)][string]$Name)
    Get-Process -Name $Name -ErrorAction SilentlyContinue
}

# Stop-ProcessByName (alias: pkill, k9): force-stops every process with that name.
function Stop-ProcessByName {
    param([Parameter(Mandatory)][string]$Name)
    Get-Process -Name $Name -ErrorAction SilentlyContinue | Stop-Process -Force
}

#endregion Unix-style text and process tools

#region Git

# Get-GitStatus (alias: gs): git status
function Get-GitStatus { git status }

# Add-GitAll (alias: ga): git add .
function Add-GitAll { git add . }

# Save-GitCommit (alias: gcom): git commit -m <message>. Named gcom because gc is a built-in alias for Get-Content.
function Save-GitCommit { git commit -m ($args -join ' ') }

# Invoke-GitPush (alias: gpush): git push with any extra arguments.
function Invoke-GitPush { git push @args }

# Invoke-GitPull (alias: gpl): git pull with any extra arguments. "gp" is a built-in read-only alias, so it can't be used.
function Invoke-GitPull { git pull @args }

# Invoke-GitCheckout (alias: gco): git checkout with any extra arguments. Example: gco main
function Invoke-GitCheckout { git checkout @args }

# Show-GitLog (alias: glog): git log with any extra arguments. "gl" is a built-in alias (Get-Location), so it can't be used.
function Show-GitLog { git log @args }

# Invoke-GitClone (alias: gcl): git clone <repo>
function Invoke-GitClone { git clone @args }

# Set-LocationGitHub (alias: g): jumps to your GitHub folder (uses zoxide if it's installed, otherwise ~\github).
function Set-LocationGitHub {
    if (Get-Command __zoxide_z -ErrorAction SilentlyContinue) {
        __zoxide_z github
    } elseif (Test-Path -Path "$HOME\github") {
        Set-Location "$HOME\github"
    }
}

# Save-GitCommitAll (alias: gcoma): git add . then git commit -m <message>
function Save-GitCommitAll {
    git add .
    git commit -m ($args -join ' ')
}

# Publish-GitChanges (alias: lazyg): git add ., git commit -m <message>, then git push
function Publish-GitChanges {
    git add .
    git commit -m ($args -join ' ')
    git push
}

#endregion Git

#region Help

# Show-Help: lists the commands in this profile.
function Show-Help {
    @'
PowerShell profile commands
===========================

Profile:
  ep / Edit-Profile                     Open this profile in the editor.
  Update-PowerShell                     Upgrade PowerShell with winget if a newer release exists.

Git:
  gs / Get-GitStatus                    git status
  ga / Add-GitAll                       git add .
  gcom <message>                        git commit -m <message>
  gpush / gpl / gcl                     git push / git pull / git clone
  gco <branch>                          git checkout <branch>
  glog                                  git log
  gcoma <message>                       git add .; git commit -m <message>
  lazyg <message>                       git add .; git commit; git push
  g                                     Go to your GitHub folder.

Files and folders:
  touch / nf <name>                     Create a file (touch also updates the timestamp).
  mkcd <dir>                            Create a folder and enter it.
  ff <name>                             Find files by name.
  unzip <file>                          Extract a zip here.
  trash <path>                          Move to the Recycle Bin.
  docs / dtop / dl                      Go to Documents or Desktop or Downloads.
  la / ll                               List files (ll includes hidden).
  df                                    Show volume information.

Text and processes:
  grep <pattern> [path]                 Search files or piped input.
  sed <f> <a> <b>                       Replace text in a file.
  head / tail <f>                       First or last lines of a file.
  which <name>                          Show where a command comes from.
  export <name> <value>                 Set an environment variable.
  pgrep / pkill <name>                  Find or force-stop processes.
  k9 <name>                             Same as pkill.

System and network:
  su / Start-AdminShell                 Open an elevated shell here.
  uptime                                Show how long the computer has been running.
  sysinfo                               Show computer information.
  flushdns                              Clear the DNS cache.
  pubip                                 Show your public IP.
  Clear-Cache                           Delete temporary files (supports -WhatIf).

Clipboard:
  cpy <text>                            Copy text.
  pst                                   Paste clipboard text.

Development:
  up [n]                                Go up n folders (default 1).
  Invoke-Cleanup                        Delete bin, obj, node_modules and packages folders.
  Test-FileChecksum (chksum)            Check a file's hash.
  Encode-Base64 (b64)                   Base64-encode text, or the clipboard if empty.
  Update-EnvPath (uenv)                 Reload PATH in this session.
  Optimize-PSReadLineHistory (upsr)     Remove duplicate history entries and trim to the limit.
  Import-TerminalIcons                  Load Terminal-Icons, or show how to install it.
  New-ApiKey (key)                      Generate a random API key (hex string).

WinGet:
  wup / wsr / wi / wun          Upgrade / search / install / uninstall packages.

Git (more):
  gpl / glog / gco <branch>     git pull / git log / git checkout.

  ht                            Show this help.
'@ | Write-Host
}

#endregion Help

#region Aliases

Set-Alias -Name ep -Value Edit-Profile
Set-Alias -Name su -Value Start-AdminShell
Set-Alias -Name uptime -Value Get-SystemUptime
Set-Alias -Name sysinfo -Value Get-SystemInfo
Set-Alias -Name flushdns -Value Clear-DnsCache
Set-Alias -Name pubip -Value Get-PublicIP
Set-Alias -Name cpy -Value Copy-ClipboardText
Set-Alias -Name pst -Value Get-ClipboardText
Set-Alias -Name uenv -Value Update-EnvPath

Set-Alias -Name touch -Value Set-FileTimestamp
Set-Alias -Name nf -Value New-File
Set-Alias -Name mkcd -Value New-DirectoryAndEnter
Set-Alias -Name ff -Value Find-FileByName
Set-Alias -Name unzip -Value Expand-ZipHere
Set-Alias -Name unzipto -Value Expand-ZipToFolder
Set-Alias -Name trash -Value Remove-ToRecycleBin
Set-Alias -Name docs -Value Set-LocationDocuments
Set-Alias -Name dtop -Value Set-LocationDesktop
Set-Alias -Name dl -Value Set-LocationDownloads
Set-Alias -Name la -Value Get-ChildItemTable
Set-Alias -Name ll -Value Get-ChildItemAll
Set-Alias -Name df -Value Get-VolumeInfo
Set-Alias -Name up -Value Move-Up
Set-Alias -Name dev -Value Set-DevFolder
Set-Alias -Name b64 -Value Encode-Base64
Set-Alias -Name chksum -Value Test-FileChecksum
Set-Alias -Name key -Value New-ApiKey

Set-Alias -Name upsr -Value Optimize-PSReadLineHistory

Set-Alias -Name wup -Value Update-WinGetPackage
Set-Alias -Name wsr -Value Search-WinGetPackage
Set-Alias -Name wi -Value Install-WinGetPackage
Set-Alias -Name wun -Value Uninstall-WinGetPackage

Set-Alias -Name grep -Value Search-Text
Set-Alias -Name sed -Value Update-FileText
Set-Alias -Name head -Value Get-FileHead
Set-Alias -Name tail -Value Get-FileTail
Set-Alias -Name which -Value Get-CommandSource
Set-Alias -Name export -Value Set-EnvVariable
Set-Alias -Name pgrep -Value Get-ProcessByName
Set-Alias -Name pkill -Value Stop-ProcessByName

Set-Alias -Name gs -Value Get-GitStatus
Set-Alias -Name ga -Value Add-GitAll
Set-Alias -Name gcom -Value Save-GitCommit
Set-Alias -Name gpush -Value Invoke-GitPush
Set-Alias -Name gpl -Value Invoke-GitPull
Set-Alias -Name gco -Value Invoke-GitCheckout
Set-Alias -Name glog -Value Show-GitLog
Set-Alias -Name gcl -Value Invoke-GitClone
Set-Alias -Name g -Value Set-LocationGitHub
Set-Alias -Name gcoma -Value Save-GitCommitAll
Set-Alias -Name lazyg -Value Publish-GitChanges
Set-Alias -Name cl -Value Get-Changelog

Set-Alias -Name ht -Value Show-Help

#endregion Aliases

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

Import-TerminalIcons
Initialize-PSReadLine
Register-CustomCompletion
Initialize-PromptTool

if ($isInteractiveShell) {
    Write-Host "Use 'Show-Help' to display the commands" -ForegroundColor Yellow
}
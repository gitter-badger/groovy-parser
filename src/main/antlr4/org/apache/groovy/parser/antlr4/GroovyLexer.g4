/*
 [The "BSD licence"]
 Copyright (c) 2013 Terence Parr, Sam Harwell
 Copyright (c) 2016 Daniel Sun
 All rights reserved.
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
 3. The name of the author may not be used to endorse or promote products
    derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/**
 * The Groovy grammar is based on the official grammar for Java(https://github.com/antlr/grammars-v4/blob/master/java/Java.g4)
 *
 * @author <a href="mailto:realbluesun@hotmail.com">Daniel.Sun</a>
 * Created on   2016/08/14
 *
 */
lexer grammar GroovyLexer;

options {
    superClass = AbstractLexer;
}

@header {
    import static org.apache.groovy.parser.antlr4.SemanticPredicates.*;
    import java.util.Deque;
    import java.util.ArrayDeque;
    import java.util.Map;
    import java.util.HashMap;
    import java.util.Set;
    import java.util.HashSet;
    import java.util.Collections;
    import java.util.Arrays;
}

@members {
    private long tokenIndex     = 0;
    private int  lastTokenType  = 0;

    /**
     * Record the index and token type of the current token while emitting tokens.
     */
    @Override
    public void emit(Token token) {
        this.tokenIndex++;

        int tokenType = token.getType();
        if (Token.DEFAULT_CHANNEL == token.getChannel()) {
            this.lastTokenType = tokenType;
        }

        if (RollBackOne == tokenType) {
            this.rollbackOneChar();
        }

        super.emit(token);
    }

    private static final Set<Integer> REGEX_CHECK_SET =
                                            Collections.unmodifiableSet(
                                                new HashSet<>(Arrays.asList(Identifier, CapitalizedIdentifier, NullLiteral, BooleanLiteral, THIS, RPAREN, RBRACK, RBRACE, IntegerLiteral, FloatingPointLiteral, StringLiteral, GStringEnd, INC, DEC)));
    private boolean isRegexAllowed() {
        if (REGEX_CHECK_SET.contains(this.lastTokenType)) {
            return false;
        }

        return true;
    }

    /**
     * just a hook, which will be overrided by GroovyLangLexer
     */
    protected void rollbackOneChar() {}

    private static class Paren {
        private String text;
        private int lastTokenType;
        private int line;
        private int column;

        public Paren(String text, int lastTokenType, int line, int column) {
            this.text = text;
            this.lastTokenType = lastTokenType;
            this.line = line;
            this.column = column;
        }

        public String getText() {
            return this.text;
        }

        public int getLastTokenType() {
            return this.lastTokenType;
        }

        public int getLine() {
            return line;
        }

        public int getColumn() {
            return column;
        }

        @Override
        public int hashCode() {
            return (int) (text.hashCode() * line + column);
        }

        @Override
        public boolean equals(Object obj) {
            if (!(obj instanceof Paren)) {
                return false;
            }

            Paren other = (Paren) obj;

            return this.text.equals(other.text) && (this.line == other.line && this.column == other.column);
        }
    }

    private static final Map<String, String> PAREN_MAP = Collections.unmodifiableMap(new HashMap<String, String>() {
        {
            put("(", ")");
            put("[", "]");
            put("{", "}");
        }
    });

    private final Deque<Paren> parenStack = new ArrayDeque<>(32);
    private void enterParen() {
        parenStack.push(new Paren(getText(), this.lastTokenType, getLine(), getCharPositionInLine() + 1));
    }
    private void exitParen() {
        Paren paren = parenStack.peek();
        String text = getText();

        require(null != paren, "Too many '" + text + "'");
        require(text.equals(PAREN_MAP.get(paren.getText())),
                "'" + text + "' " + genPositionInfo() + " can not match '" + paren.getText() + "' " + formatPositionInfo(paren.getLine(), paren.getColumn()),
                false);

        parenStack.pop();
    }
    private boolean isInsideParens() {
        Paren paren = parenStack.peek();

        // We just care about "(" and "[", inside which the new lines will be ignored.
        // Notice: the new lines between "{" and "}" can not be ignored.
        if (null == paren) {
            return false;
        }
        return ("(".equals(paren.getText()) && TRY != paren.getLastTokenType()) // we don't treat try-paren(i.e. try (....)) as parenthesis
                    || "[".equals(paren.getText());
    }
    private void ignoreTokenInsideParens() {
        if (!this.isInsideParens()) {
            return;
        }

        this.setChannel(Token.HIDDEN_CHANNEL);
    }
    private void ignoreMultiLineCommentConditionally() {
        if (!this.isInsideParens() && isFollowedByWhiteSpaces(_input)) {
            return;
        }

        this.setChannel(Token.HIDDEN_CHANNEL);
    }

    @Override
    public int getSyntaxErrorSource() {
        return GroovySyntaxError.LEXER;
    }

    @Override
    public String genPositionInfo() {
        return formatPositionInfo(getLine(), getCharPositionInLine() + 1);
    }
}


// §3.10.5 String Literals

StringLiteral
    :   '"'      DqStringCharacter*?           '"'
    |   '\''     SqStringCharacter*?           '\''

    |   '/'      { this.isRegexAllowed() && _input.LA(1) != '*' }?
                 SlashyStringCharacter+?       '/'

    |   '"""'    TdqStringCharacter*?          '"""'
    |   '\'\'\'' TsqStringCharacter*?          '\'\'\''
    |   '$/'     DollarSlashyStringCharacter+? '/$'
    ;

// Groovy gstring
GStringBegin
    :   '"' DqStringCharacter*? DOLLAR -> pushMode(DQ_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
TdqGStringBegin
    :   '"""'   TdqStringCharacter*? DOLLAR -> type(GStringBegin), pushMode(TDQ_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
SlashyGStringBegin
    :   '/' { this.isRegexAllowed() && _input.LA(1) != '*' }? SlashyStringCharacter*? DOLLAR { isFollowedByJavaLetterInGString(_input) }? -> type(GStringBegin), pushMode(SLASHY_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
DollarSlashyGStringBegin
    :   '$/' DollarSlashyStringCharacter*? DOLLAR { isFollowedByJavaLetterInGString(_input) }? -> type(GStringBegin), pushMode(DOLLAR_SLASHY_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;

mode DQ_GSTRING_MODE;
GStringEnd
    :   '"'     -> popMode
    ;
GStringPart
    :   DOLLAR  -> pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
GStringCharacter
    :   DqStringCharacter -> more
    ;

mode TDQ_GSTRING_MODE;
TdqGStringEnd
    :   '"""'    -> type(GStringEnd), popMode
    ;
TdqGStringPart
    :   DOLLAR   -> type(GStringPart), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
TdqGStringCharacter
    :   TdqStringCharacter -> more
    ;

mode SLASHY_GSTRING_MODE;
SlashyGStringEnd
    :   '$'? '/'  -> type(GStringEnd), popMode
    ;
SlashyGStringPart
    :   DOLLAR { isFollowedByJavaLetterInGString(_input) }?   -> type(GStringPart), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
SlashyGStringCharacter
    :   SlashyStringCharacter -> more
    ;

mode DOLLAR_SLASHY_GSTRING_MODE;
DollarSlashyGStringEnd
    :   '/$'      -> type(GStringEnd), popMode
    ;
DollarSlashyGStringPart
    :   DOLLAR { isFollowedByJavaLetterInGString(_input) }?   -> type(GStringPart), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
DollarSlashyGStringCharacter
    :   DollarSlashyStringCharacter -> more
    ;

mode GSTRING_TYPE_SELECTOR_MODE;
GStringLBrace
    :   '{' { this.enterParen();  } -> type(LBRACE), popMode, pushMode(DEFAULT_MODE)
    ;
GStringIdentifier
    :   IdentifierInGString -> type(Identifier), popMode, pushMode(GSTRING_PATH_MODE)
    ;


mode GSTRING_PATH_MODE;
GStringPathPart
    :   '.' IdentifierInGString
    ;
RollBackOne
    :   . -> popMode, channel(HIDDEN)
    ;


mode DEFAULT_MODE;
// character in the double quotation string. e.g. "a"
fragment
DqStringCharacter
    :   ~["\\$]
    |   EscapeSequence
    ;

// character in the single quotation string. e.g. 'a'
fragment
SqStringCharacter
    :   ~['\\]
    |   EscapeSequence
    ;

// character in the triple double quotation string. e.g. """a"""
fragment TdqStringCharacter
    :   ~["\\$]
    |   '"' { !(_input.LA(1) == '"' && _input.LA(2) == '"') }?
    |   EscapeSequence
    ;

// character in the triple single quotation string. e.g. '''a'''
fragment TsqStringCharacter
    :   ~['\\]
    |   '\'' { !(_input.LA(1) == '\'' && _input.LA(2) == '\'') }?
    |   EscapeSequence
    ;

// character in the slashy string. e.g. /a/
fragment SlashyStringCharacter
    :   SlashEscape
    |   '$' { !isFollowedByJavaLetterInGString(_input) }?
    |   ~[/$\u0000]
    ;

// character in the collar slashy string. e.g. $/a/$
fragment DollarSlashyStringCharacter
    :   SlashEscape | DollarSlashEscape | DollarDollarEscape
    |   '/' { _input.LA(1) != '$' }?
    |   '$' { !isFollowedByJavaLetterInGString(_input) }?
    |   ~[/$\u0000]
    ;

// Groovy keywords
AS              : 'as';
DEF             : 'def';
IN              : 'in';
TRAIT           : 'trait';


// §3.9 Keywords
BuiltInPrimitiveType
    :   BOOLEAN
    |   CHAR
    |   BYTE
    |   SHORT
    |   INT
    |   LONG
    |   FLOAT
    |   DOUBLE
    ;

ABSTRACT      : 'abstract';
ASSERT        : 'assert';

fragment
BOOLEAN       : 'boolean';

BREAK         : 'break';

fragment
BYTE          : 'byte';

CASE          : 'case';
CATCH         : 'catch';

fragment
CHAR          : 'char';

CLASS         : 'class';
CONST         : 'const';
CONTINUE      : 'continue';
DEFAULT       : 'default';
DO            : 'do';

fragment
DOUBLE        : 'double';

ELSE          : 'else';
ENUM          : 'enum';
EXTENDS       : 'extends';
FINAL         : 'final';
FINALLY       : 'finally';

fragment
FLOAT         : 'float';


FOR           : 'for';
IF            : 'if';
GOTO          : 'goto';
IMPLEMENTS    : 'implements';
IMPORT        : 'import';
INSTANCEOF    : 'instanceof';

fragment
INT           : 'int';

INTERFACE     : 'interface';

fragment
LONG          : 'long';

NATIVE        : 'native';
NEW           : 'new';
PACKAGE       : 'package';
PRIVATE       : 'private';
PROTECTED     : 'protected';
PUBLIC        : 'public';
RETURN        : 'return';

fragment
SHORT         : 'short';


STATIC        : 'static';
STRICTFP      : 'strictfp';
SUPER         : 'super';
SWITCH        : 'switch';
SYNCHRONIZED  : 'synchronized';
THIS          : 'this';
THROW         : 'throw';
THROWS        : 'throws';
TRANSIENT     : 'transient';
TRY           : 'try';
VOID          : 'void';
VOLATILE      : 'volatile';
WHILE         : 'while';


// §3.10.1 Integer Literals

IntegerLiteral
    :   DecimalIntegerLiteral
    |   HexIntegerLiteral
    |   OctalIntegerLiteral
    |   BinaryIntegerLiteral
    ;

fragment
DecimalIntegerLiteral
    :   DecimalNumeral IntegerTypeSuffix?
    ;

fragment
HexIntegerLiteral
    :   HexNumeral IntegerTypeSuffix?
    ;

fragment
OctalIntegerLiteral
    :   OctalNumeral IntegerTypeSuffix?
    ;

fragment
BinaryIntegerLiteral
    :   BinaryNumeral IntegerTypeSuffix?
    ;

fragment
IntegerTypeSuffix
    :   [lLiIgG]
    ;

fragment
DecimalNumeral
    :   '0'
    |   NonZeroDigit (Digits? | Underscores Digits)
    ;

fragment
Digits
    :   Digit (DigitOrUnderscore* Digit)?
    ;

fragment
Digit
    :   '0'
    |   NonZeroDigit
    ;

fragment
NonZeroDigit
    :   [1-9]
    ;

fragment
DigitOrUnderscore
    :   Digit
    |   '_'
    ;

fragment
Underscores
    :   '_'+
    ;

fragment
HexNumeral
    :   '0' [xX] HexDigits
    ;

fragment
HexDigits
    :   HexDigit (HexDigitOrUnderscore* HexDigit)?
    ;

fragment
HexDigit
    :   [0-9a-fA-F]
    ;

fragment
HexDigitOrUnderscore
    :   HexDigit
    |   '_'
    ;

fragment
OctalNumeral
    :   '0' Underscores? OctalDigits
    ;

fragment
OctalDigits
    :   OctalDigit (OctalDigitOrUnderscore* OctalDigit)?
    ;

fragment
OctalDigit
    :   [0-7]
    ;

fragment
OctalDigitOrUnderscore
    :   OctalDigit
    |   '_'
    ;

fragment
BinaryNumeral
    :   '0' [bB] BinaryDigits
    ;

fragment
BinaryDigits
    :   BinaryDigit (BinaryDigitOrUnderscore* BinaryDigit)?
    ;

fragment
BinaryDigit
    :   [01]
    ;

fragment
BinaryDigitOrUnderscore
    :   BinaryDigit
    |   '_'
    ;

// §3.10.2 Floating-Point Literals

FloatingPointLiteral
    :   DecimalFloatingPointLiteral
    |   HexadecimalFloatingPointLiteral
    ;

fragment
DecimalFloatingPointLiteral
    :   Digits '.' Digits ExponentPart? FloatTypeSuffix?
    |   Digits ExponentPart FloatTypeSuffix?
    |   Digits FloatTypeSuffix
    ;

fragment
ExponentPart
    :   ExponentIndicator SignedInteger
    ;

fragment
ExponentIndicator
    :   [eE]
    ;

fragment
SignedInteger
    :   Sign? Digits
    ;

fragment
Sign
    :   [+-]
    ;

fragment
FloatTypeSuffix
    :   [fFdDgG]
    ;

fragment
HexadecimalFloatingPointLiteral
    :   HexSignificand BinaryExponent FloatTypeSuffix?
    ;

fragment
HexSignificand
    :   HexNumeral '.'?
    |   '0' [xX] HexDigits? '.' HexDigits
    ;

fragment
BinaryExponent
    :   BinaryExponentIndicator SignedInteger
    ;

fragment
BinaryExponentIndicator
    :   [pP]
    ;

// §3.10.3 Boolean Literals

BooleanLiteral
    :   'true'
    |   'false'
    ;


// §3.10.6 Escape Sequences for Character and String Literals

fragment
EscapeSequence
    :   '\\' [btnfr"'\\]
    |   OctalEscape
    |   UnicodeEscape
    |   DollarEscape
    |   LineEscape
    ;


fragment
OctalEscape
    :   '\\' OctalDigit
    |   '\\' OctalDigit OctalDigit
    |   '\\' ZeroToThree OctalDigit OctalDigit
    ;

// Groovy allows 1 or more u's after the backslash
fragment
UnicodeEscape
    :   '\\' 'u'+ HexDigit HexDigit HexDigit HexDigit
    ;

fragment
ZeroToThree
    :   [0-3]
    ;

// Groovy Escape Sequences

fragment
DollarEscape
    :   '\\' DOLLAR
    ;

fragment
LineEscape
    :   '\\' '\r'? '\n'
    ;

fragment
SlashEscape
    :   '\\' '/'
    ;

fragment
DollarSlashEscape
    :   '$/$'
    ;

fragment
DollarDollarEscape
    :   '$$'
    ;
// §3.10.7 The Null Literal

NullLiteral
    :   'null'
    ;

// Groovy Operators

RANGE_INCLUSIVE     : '..';
RANGE_EXCLUSIVE     : '..<';
SPREAD_DOT          : '*.';
SAFE_DOT            : '?.';
ELVIS               : '?:';
METHOD_POINTER      : '.&';
METHOD_REFERENCE    : '::';
REGEX_FIND          : '=~';
REGEX_MATCH         : '==~';
POWER               : '**';
POWER_ASSIGN        : '**=';
SPACESHIP           : '<=>';
IDENTICAL           : '===';
NOT_IDENTICAL       : '!==';
ARROW               : '->';

// !internalPromise will be parsed as !in ternalPromise, so semantic predicates are necessary
NOT_INSTANCEOF      : '!instanceof' { isFollowedBy(_input, ' ', '\t', '\r', '\n') }?;
NOT_IN              : '!in'         { isFollowedBy(_input, ' ', '\t', '\r', '\n', '[', '(', '{') }?;

fragment
DOLLAR              : '$';


// §3.11 Separators

LPAREN          : '('  { this.enterParen();     } -> pushMode(DEFAULT_MODE);
RPAREN          : ')'  { this.exitParen();      } -> popMode;
LBRACE          : '{'  { this.enterParen();     } -> pushMode(DEFAULT_MODE);
RBRACE          : '}'  { this.exitParen();      } -> popMode;
LBRACK          : '['  { this.enterParen();     } -> pushMode(DEFAULT_MODE);
RBRACK          : ']'  { this.exitParen();      } -> popMode;

SEMI            : ';';
COMMA           : ',';
DOT             : '.';

// §3.12 Operators

ASSIGN          : '=';
GT              : '>';
LT              : '<';
NOT             : '!';
BITNOT          : '~';
QUESTION        : '?';
COLON           : ':';
EQUAL           : '==';
LE              : '<=';
GE              : '>=';
NOTEQUAL        : '!=';
AND             : '&&';
OR              : '||';
INC             : '++';
DEC             : '--';
ADD             : '+';
SUB             : '-';
MUL             : '*';
DIV             : '/';
BITAND          : '&';
BITOR           : '|';
XOR             : '^';
MOD             : '%';


ADD_ASSIGN      : '+=';
SUB_ASSIGN      : '-=';
MUL_ASSIGN      : '*=';
DIV_ASSIGN      : '/=';
AND_ASSIGN      : '&=';
OR_ASSIGN       : '|=';
XOR_ASSIGN      : '^=';
MOD_ASSIGN      : '%=';
LSHIFT_ASSIGN   : '<<=';
RSHIFT_ASSIGN   : '>>=';
URSHIFT_ASSIGN  : '>>>=';
ELVIS_ASSIGN    : '?=';


// §3.8 Identifiers (must appear after all keywords in the grammar)
CapitalizedIdentifier
    :   [A-Z] JavaLetterOrDigit*

    // FIXME REMOVE THE FOLLOWING ALTERNATIVE. Groovy's identifier can be unicode escape(e.g. def \u4e00\u9fa5 = '123'), which will impact the performance and is pointless to support IMO
    |   [A-Z] (JavaLetterOrDigit | UnicodeEscape)*
    ;

Identifier
    :   JavaLetter JavaLetterOrDigit*

    // FIXME REMOVE THE FOLLOWING ALTERNATIVE. Groovy's identifier can be unicode escape(e.g. def \u4e00\u9fa5 = '123'), which will impact the performance and is pointless to support IMO
    |   (JavaLetter | UnicodeEscape) (JavaLetterOrDigit | UnicodeEscape)*
    ;

fragment
IdentifierInGString
    :   JavaLetterInGString JavaLetterOrDigitInGString*
    ;

fragment
JavaLetterInGString
    :   [a-zA-Z_] // these are the "java letters" below 0x7F, except for $
    |   // covers all characters above 0x7F which are not a surrogate
        ~[\u0000-\u007F\uD800-\uDBFF]
        {Character.isJavaIdentifierStart(_input.LA(-1))}?
    |   // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
        [\uD800-\uDBFF] [\uDC00-\uDFFF]
        {Character.isJavaIdentifierStart(Character.toCodePoint((char)_input.LA(-2), (char)_input.LA(-1)))}?
    ;

fragment
JavaLetterOrDigitInGString
    :   [a-zA-Z0-9_] // these are the "java letters or digits" below 0x7F, except for $
    |   // covers all characters above 0x7F which are not a surrogate
        ~[\u0000-\u007F\uD800-\uDBFF]
        {Character.isJavaIdentifierPart(_input.LA(-1))}?
    |   // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
        [\uD800-\uDBFF] [\uDC00-\uDFFF]
        {Character.isJavaIdentifierPart(Character.toCodePoint((char)_input.LA(-2), (char)_input.LA(-1)))}?
    ;


fragment
JavaLetter
    :   [a-zA-Z$_] // these are the "java letters" below 0x7F
    |   // covers all characters above 0x7F which are not a surrogate
        ~[\u0000-\u007F\uD800-\uDBFF]
        {Character.isJavaIdentifierStart(_input.LA(-1))}?
    |   // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
        [\uD800-\uDBFF] [\uDC00-\uDFFF]
        {Character.isJavaIdentifierStart(Character.toCodePoint((char)_input.LA(-2), (char)_input.LA(-1)))}?
    ;

fragment
JavaLetterOrDigit
    :   [a-zA-Z0-9$_] // these are the "java letters or digits" below 0x7F
    |   // covers all characters above 0x7F which are not a surrogate
        ~[\u0000-\u007F\uD800-\uDBFF]
        {Character.isJavaIdentifierPart(_input.LA(-1))}?
    |   // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
        [\uD800-\uDBFF] [\uDC00-\uDFFF]
        {Character.isJavaIdentifierPart(Character.toCodePoint((char)_input.LA(-2), (char)_input.LA(-1)))}?
    ;

//
// Additional symbols not defined in the lexical specification
//

AT : '@';
ELLIPSIS : '...';

//
// Whitespace, line escape and comments
//
WS  :  ([ \t\u000C]+ | LineEscape+)     -> skip
    ;


// Inside (...) and [...] but not {...}, ignore newlines.
NL  : '\r'? '\n'            { this.ignoreTokenInsideParens(); }
    ;

// Multiple-line comments(including groovydoc comments)
ML_COMMENT
    :   '/*' .*? '*/'       { this.ignoreMultiLineCommentConditionally(); } -> type(NL)
    ;

// Single-line comments
SL_COMMENT
    :   '//' ~[\r\n\uFFFF]* { this.ignoreTokenInsideParens(); }             -> type(NL)
    ;

// Script-header comments.
// The very first characters of the file may be "#!".  If so, ignore the first line.
SH_COMMENT
    :   '#!' { 0 == this.tokenIndex }?<fail={"Shebang comment should appear at the first line"}> ~[\r\n\uFFFF]* -> skip
    ;

// Unexpected characters will be handled by groovy parser later.
UNEXPECTED_CHAR
    :   .
    ;

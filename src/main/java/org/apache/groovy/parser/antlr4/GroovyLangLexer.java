package org.apache.groovy.parser.antlr4;

import org.antlr.v4.runtime.CharStream;
import org.antlr.v4.runtime.Lexer;
import org.antlr.v4.runtime.atn.ATN;
import org.antlr.v4.runtime.atn.LexerATNSimulator;
import org.antlr.v4.runtime.atn.PredictionContextCache;
import org.antlr.v4.runtime.dfa.DFA;

/**
 * The lexer for Groovy programming language, which is based on the lexer generated by Antlr4
 *
 * @author <a href="mailto:realbluesun@hotmail.com">Daniel.Sun</a>
 * @date 2016/08/14
 */
public class GroovyLangLexer extends GroovyLexer {
    public GroovyLangLexer(CharStream input) {
        super(input);

        AntlrCacheManager acm = new AntlrCacheManager(this);
        this.setInterpreter(
                new PositionAdjustingLexerATNSimulator(
                        this,
                        this.getATN(),
                        acm.createDecisionToDFA(),
                        acm.createPredictionContextCache()
                )
        );
    }

    @Override
    protected void rollbackOneChar() {
        ((PositionAdjustingLexerATNSimulator) getInterpreter()).resetAcceptPosition(getInputStream(), _tokenStartCharIndex - 1, _tokenStartLine, _tokenStartCharPositionInLine - 1);
    }

    private static class PositionAdjustingLexerATNSimulator extends LexerATNSimulator {
        public PositionAdjustingLexerATNSimulator(Lexer recog, ATN atn, DFA[] decisionToDFA, PredictionContextCache sharedContextCache) {
            super(recog, atn, decisionToDFA, sharedContextCache);
        }

        protected void resetAcceptPosition(CharStream input, int index, int line, int charPositionInLine) {
            input.seek(index);
            this.line = line;
            this.charPositionInLine = charPositionInLine;
            this.consume(input);
        }
    }
}

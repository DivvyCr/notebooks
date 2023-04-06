package com.dvc.notes.admonition.internal;

import com.dvc.notes.admonition.AdmonitionExtension;
import com.vladsch.flexmark.util.data.DataHolder;

import java.util.Map;

public class AdmonitionOptions {
    final public int contentIndent;
    final public boolean allowLeadingSpace;
    final public boolean interruptsParagraph;
    final public boolean interruptsItemParagraph;
    final public boolean withSpacesInterruptsItemParagraph;
    final public boolean allowLazyContinuation;
    final public String unresolvedQualifier;
    final public Map<String, String> qualifierTypeMap;

    public AdmonitionOptions(DataHolder options) {
        contentIndent = AdmonitionExtension.CONTENT_INDENT.get(options);
        allowLeadingSpace = AdmonitionExtension.ALLOW_LEADING_SPACE.get(options);
        interruptsParagraph = AdmonitionExtension.INTERRUPTS_PARAGRAPH.get(options);
        interruptsItemParagraph = AdmonitionExtension.INTERRUPTS_ITEM_PARAGRAPH.get(options);
        withSpacesInterruptsItemParagraph = AdmonitionExtension.WITH_SPACES_INTERRUPTS_ITEM_PARAGRAPH.get(options);
        allowLazyContinuation = AdmonitionExtension.ALLOW_LAZY_CONTINUATION.get(options);
        unresolvedQualifier = AdmonitionExtension.UNRESOLVED_QUALIFIER.get(options);
        qualifierTypeMap = AdmonitionExtension.QUALIFIER_TYPE_MAP.get(options);
    }
}

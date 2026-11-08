// STUB: pulldown-cmark's untranslated CommonMark parser is supplied by vendored
// MD4C 0.5.3 (MIT). This adapter only uses the CommonMark, table, and strike flags;
// Upstream source: https://github.com/mity/md4c/tree/release-0.5.3/src
// it collects typed events before the borrowed input or MD4C scratch data expires.
// MD4C has its own documented code-span/table complexity limits and may differ
// from pulldown-cmark at pathological or implementation-specific Markdown edges.
#ifndef CODEX_CLIPBOARD_HTML_NATIVE_H
#define CODEX_CLIPBOARD_HTML_NATIVE_H
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "clipboard_html_native/md4c.c"
#include "clipboard_html_native/entities.h"

typedef struct CodexClipboardNativeEvent {
    int kind, tag, level, ordered, code_kind;
    uint64_t list_start;
    char *text, *destination, *title;
    unsigned char *text_entity_starts, *destination_entity_starts, *title_entity_starts;
    size_t text_length, destination_length, title_length;
    int *alignments;
    size_t alignment_count;
} CodexClipboardNativeEvent;

typedef struct CodexClipboardNativeParser {
    CodexClipboardNativeEvent *events;
    size_t count, capacity;
    int *blocks, *tight, *ignored;
    size_t depth, stack_capacity;
    size_t table_index, table_cell, code_index;
    int in_header, in_code_span;
} CodexClipboardNativeParser;

static int codex_clipboard_copy(char **out, size_t *size, const char *text, size_t length) {
    if (length > SIZE_MAX - *size - 1) return -1;
    char *next = (char *)realloc(*out, *size + length + 1);
    if (!next) return -1;
    if (length) memcpy(next + *size, text, length);
    *size += length; next[*size] = 0; *out = next; return 0;
}

// Preserve MD4C attribute substring classifications: an escaped ampersand is
// literal text and must not accidentally become an entity during V decoding.
static int codex_clipboard_attribute(char **out, size_t *length, unsigned char **entity_starts, const MD_ATTRIBUTE *attribute) {
    if(codex_clipboard_copy(out,length,attribute->text,attribute->size)) return -1;
    if(!attribute->size) return 0;
    *entity_starts=(unsigned char *)calloc(attribute->size,1);if(!*entity_starts)return -1;
    for(size_t part=0;attribute->substr_offsets[part] < attribute->size;part++)
        if(attribute->substr_types[part]==MD_TEXT_ENTITY) (*entity_starts)[attribute->substr_offsets[part]]=1;
    return 0;
}

static CodexClipboardNativeEvent *codex_clipboard_event(CodexClipboardNativeParser *p, int kind, int tag) {
    if(p->count == p->capacity) {
        size_t capacity = p->capacity ? p->capacity * 2 : 32;
        void *next = realloc(p->events, capacity * sizeof(*p->events));
        if(!next) return NULL;
        p->events = (CodexClipboardNativeEvent *)next; p->capacity = capacity;
    }
    CodexClipboardNativeEvent *e = &p->events[p->count++];
    memset(e, 0, sizeof(*e)); e->kind = kind; e->tag = tag; return e;
}

static int codex_clipboard_stack(CodexClipboardNativeParser *p, int block, int tight, int ignored) {
    if(p->depth == p->stack_capacity) {
        size_t capacity = p->stack_capacity ? p->stack_capacity * 2 : 32;
        int *blocks = (int *)realloc(p->blocks, capacity * sizeof(int));
        if(!blocks) return -1; p->blocks = blocks;
        int *tights = (int *)realloc(p->tight, capacity * sizeof(int));
        if(!tights) return -1; p->tight = tights;
        int *ignores = (int *)realloc(p->ignored, capacity * sizeof(int));
        if(!ignores) return -1; p->ignored = ignores; p->stack_capacity = capacity;
    }
    p->blocks[p->depth] = block; p->tight[p->depth] = tight; p->ignored[p->depth] = ignored; p->depth++;
    return 0;
}

static int codex_clipboard_block_tag(MD_BLOCKTYPE type) {
    switch(type) {
        case MD_BLOCK_QUOTE:return 2; case MD_BLOCK_UL:case MD_BLOCK_OL:return 5;
        case MD_BLOCK_LI:return 6; case MD_BLOCK_H:return 1; case MD_BLOCK_CODE:return 3;
        case MD_BLOCK_HTML:return 4; case MD_BLOCK_P:return 0; case MD_BLOCK_TABLE:return 8;
        case MD_BLOCK_THEAD:return 9; case MD_BLOCK_TR:return 10;
        case MD_BLOCK_TH:case MD_BLOCK_TD:return 11; default:return -1;
    }
}

static int codex_clipboard_enter_block(MD_BLOCKTYPE type, void *detail, void *userdata) {
    CodexClipboardNativeParser *p = (CodexClipboardNativeParser *)userdata;
    int tight = type == MD_BLOCK_UL ? ((MD_BLOCK_UL_DETAIL *)detail)->is_tight :
        type == MD_BLOCK_OL ? ((MD_BLOCK_OL_DETAIL *)detail)->is_tight : 0;
    int ignore = type == MD_BLOCK_DOC || type == MD_BLOCK_TBODY ||
        (type == MD_BLOCK_TR && p->in_header) ||
        (type == MD_BLOCK_P && p->depth >= 2 && p->blocks[p->depth-1] == MD_BLOCK_LI && p->tight[p->depth-2]);
    if(codex_clipboard_stack(p, type, tight, ignore)) return -1;
    if(ignore) return 0;
    if(type == MD_BLOCK_HR) return codex_clipboard_event(p, 9, 0) ? 0 : -1;
    int tag = codex_clipboard_block_tag(type); if(tag < 0) return -1;
    CodexClipboardNativeEvent *e = codex_clipboard_event(p, 0, tag); if(!e) return -1;
    if(type == MD_BLOCK_H) e->level = ((MD_BLOCK_H_DETAIL *)detail)->level;
    if(type == MD_BLOCK_OL) {e->ordered=1;e->list_start=((MD_BLOCK_OL_DETAIL *)detail)->start;}
    if(type == MD_BLOCK_CODE) {
        MD_BLOCK_CODE_DETAIL *d=(MD_BLOCK_CODE_DETAIL *)detail; e->code_kind=d->fence_char!=0;
        if(codex_clipboard_attribute(&e->text,&e->text_length,&e->text_entity_starts,&d->info)) return -1;
    }
    if(type == MD_BLOCK_TABLE) {
        p->table_index=p->count-1;e->alignment_count=((MD_BLOCK_TABLE_DETAIL *)detail)->col_count;
        e->alignments=(int *)calloc(e->alignment_count,sizeof(int));if(!e->alignments) return -1;
    }
    if(type == MD_BLOCK_THEAD) {p->in_header=1;p->table_cell=0;}
    if(type == MD_BLOCK_TH && p->table_cell < p->events[p->table_index].alignment_count)
        p->events[p->table_index].alignments[p->table_cell++]=((MD_BLOCK_TD_DETAIL *)detail)->align;
    return 0;
}

static int codex_clipboard_leave_block(MD_BLOCKTYPE type, void *detail, void *userdata) {
    CodexClipboardNativeParser *p=(CodexClipboardNativeParser *)userdata;
    int ignore=p->ignored[--p->depth];
    if(type==MD_BLOCK_THEAD) p->in_header=0;
    if(ignore || type==MD_BLOCK_HR) return 0;
    CodexClipboardNativeEvent *e=codex_clipboard_event(p,1,codex_clipboard_block_tag(type));if(!e)return -1;
    if(type==MD_BLOCK_H) e->level=((MD_BLOCK_H_DETAIL *)detail)->level;
    e->ordered=type==MD_BLOCK_OL;return 0;
}

static int codex_clipboard_span_tag(MD_SPANTYPE type) {
    switch(type) {case MD_SPAN_EM:return 12;case MD_SPAN_STRONG:return 13;
        case MD_SPAN_A:return 15;case MD_SPAN_IMG:return 16;case MD_SPAN_DEL:return 14;default:return -1;}
}

static int codex_clipboard_enter_span(MD_SPANTYPE type, void *detail, void *userdata) {
    CodexClipboardNativeParser *p=(CodexClipboardNativeParser *)userdata;
    if(type==MD_SPAN_CODE) {p->code_index=p->count;p->in_code_span=1;return codex_clipboard_event(p,3,0)?0:-1;}
    int tag=codex_clipboard_span_tag(type);if(tag<0)return -1;
    CodexClipboardNativeEvent *e=codex_clipboard_event(p,0,tag);if(!e)return -1;
    if(type==MD_SPAN_A || type==MD_SPAN_IMG) {
        MD_ATTRIBUTE destination=type==MD_SPAN_A?((MD_SPAN_A_DETAIL *)detail)->href:((MD_SPAN_IMG_DETAIL *)detail)->src;
        MD_ATTRIBUTE title=type==MD_SPAN_A?((MD_SPAN_A_DETAIL *)detail)->title:((MD_SPAN_IMG_DETAIL *)detail)->title;
        if(codex_clipboard_attribute(&e->destination,&e->destination_length,&e->destination_entity_starts,&destination) ||
           codex_clipboard_attribute(&e->title,&e->title_length,&e->title_entity_starts,&title))return -1;
    }
    return 0;
}

static int codex_clipboard_leave_span(MD_SPANTYPE type, void *detail, void *userdata) {
    (void)detail;CodexClipboardNativeParser *p=(CodexClipboardNativeParser *)userdata;
    if(type==MD_SPAN_CODE) {p->in_code_span=0;return 0;}
    return codex_clipboard_event(p,1,codex_clipboard_span_tag(type))?0:-1;
}

static int codex_clipboard_text(MD_TEXTTYPE type,const MD_CHAR *text,MD_SIZE size,void *userdata) {
    CodexClipboardNativeParser *p=(CodexClipboardNativeParser *)userdata;
    if(p->in_code_span) return codex_clipboard_copy(&p->events[p->code_index].text,&p->events[p->code_index].text_length,text,size);
    int kind=type==MD_TEXT_BR?8:type==MD_TEXT_SOFTBR?7:type==MD_TEXT_HTML?
        (p->depth && p->blocks[p->depth-1]==MD_BLOCK_HTML?4:5):type==MD_TEXT_ENTITY?12:2;
    CodexClipboardNativeEvent *e=codex_clipboard_event(p,kind,0);if(!e)return -1;
    if(type==MD_TEXT_NULLCHAR) {text="\xef\xbf\xbd";size=3;}
    return codex_clipboard_copy(&e->text,&e->text_length,text,size);
}

static void codex_clipboard_parser_free(CodexClipboardNativeParser *p) {
    for(size_t i=0;i<p->count;i++) {free(p->events[i].text);free(p->events[i].destination);free(p->events[i].title);free(p->events[i].alignments);free(p->events[i].text_entity_starts);free(p->events[i].destination_entity_starts);free(p->events[i].title_entity_starts);}
    free(p->events);free(p->blocks);free(p->tight);free(p->ignored);free(p);
}

static CodexClipboardNativeParser *codex_clipboard_parser_new(const char *source,size_t length,unsigned flags) {
    if(length > UINT_MAX)return NULL;
    CodexClipboardNativeParser *p=(CodexClipboardNativeParser *)calloc(1,sizeof(*p));if(!p)return NULL;
    MD_PARSER parser={0};parser.flags=flags;
    parser.enter_block=codex_clipboard_enter_block;parser.leave_block=codex_clipboard_leave_block;
    parser.enter_span=codex_clipboard_enter_span;parser.leave_span=codex_clipboard_leave_span;parser.text=codex_clipboard_text;
    if(md_parse(source,(MD_SIZE)length,&parser,p)) {codex_clipboard_parser_free(p);return NULL;}
    return p;
}
#endif

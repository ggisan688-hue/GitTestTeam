package com.aicamp.changebook;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.constraints.Min;
import org.springframework.http.HttpStatus;
import java.util.*;

record NoteRange(@Min(1) int paragraphOrder, @Min(0) int startOffset, @Min(0) int endOffset) {}
record ValidatedNoteRange(List<NoteRange> ranges, List<String> parts, String text) {}

/** Uses stable paragraph offsets, never page numbers or client-supplied quotes. */
final class NoteRangeSupport {
  private static final ObjectMapper JSON = new ObjectMapper();
  static ValidatedNoteRange validate(BookParagraphRepository repository, Long bookId, List<NoteRange> ranges) {
    if (ranges == null || ranges.isEmpty() || ranges.size() > 200) throw invalid();
    var paragraphs = repository.findByBookIdOrderByParagraphOrderAsc(bookId);
    var indexes = new HashMap<Integer,Integer>();
    for (int i=0;i<paragraphs.size();i++) indexes.put(paragraphs.get(i).paragraphOrder,i);
    var parts = new ArrayList<String>();
    int previousIndex=-1;
    NoteRange previous=null;
    for (var range : ranges) {
      if (range == null) throw invalid();
      Integer index=indexes.get(range.paragraphOrder());
      if (index==null || (previous!=null && index!=previousIndex+1)) throw invalid();
      String text=paragraphs.get(index).content;
      if (text==null || range.startOffset()<0 || (range.endOffset()<=range.startOffset() && !text.isEmpty()) || range.endOffset()>text.length()) throw invalid();
      if (previous!=null && (previous.endOffset()!=paragraphs.get(previousIndex).content.length() || range.startOffset()!=0)) throw invalid();
      parts.add(text.substring(range.startOffset(),range.endOffset()));
      previous=range; previousIndex=index;
    }
    if(parts.get(0).isEmpty() || parts.get(parts.size()-1).isEmpty()) throw invalid();
    String text=String.join("\n\n",parts);
    if (text.length()>30000) throw new ApiException(HttpStatus.BAD_REQUEST,"SELECTION_TOO_LONG","한 번에 선택할 수 있는 문장은 30,000자까지입니다.");
    return new ValidatedNoteRange(List.copyOf(ranges),List.copyOf(parts),text);
  }
  static String encode(List<NoteRange> ranges) {
    try { return JSON.writeValueAsString(ranges); }
    catch (Exception error) { throw new IllegalStateException("Cannot encode note ranges",error); }
  }
  static List<NoteRange> decode(String json) {
    if (json==null || json.isBlank()) return List.of();
    try { return JSON.readValue(json,new TypeReference<List<NoteRange>>(){}); }
    catch (Exception error) { throw new IllegalStateException("Cannot decode note ranges",error); }
  }
  private static ApiException invalid() { return new ApiException(HttpStatus.BAD_REQUEST,"INVALID_NOTE_RANGE","선택 범위를 확인해 주세요."); }
}

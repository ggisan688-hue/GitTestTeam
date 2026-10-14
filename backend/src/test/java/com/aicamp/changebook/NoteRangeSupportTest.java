package com.aicamp.changebook;

import org.junit.jupiter.api.Test;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class NoteRangeSupportTest {
  private BookParagraph paragraph(int order, String text) {
    var p=new BookParagraph(); p.paragraphOrder=order; p.content=text; return p;
  }
  private BookParagraphRepository source() {
    var repository=mock(BookParagraphRepository.class);
    when(repository.findByBookIdOrderByParagraphOrderAsc(1L)).thenReturn(List.of(
        paragraph(10,"first paragraph"),paragraph(20,"middle"),paragraph(30,"last paragraph")));
    return repository;
  }
  @Test void joinsConsecutiveParagraphsWithStableOffsetsEvenWhenOrdersHaveGaps() {
    var value=NoteRangeSupport.validate(source(),1L,List.of(
        new NoteRange(10,6,15),new NoteRange(20,0,6),new NoteRange(30,0,4)));
    assertEquals("paragraph\n\nmiddle\n\nlast",value.text());
    assertEquals(3,value.ranges().size());
    assertEquals(value.ranges(),NoteRangeSupport.decode(NoteRangeSupport.encode(value.ranges())));
  }
  @Test void rejectsSkippedMiddleTextAndReversedOrOutOfBoundsSelection() {
    assertThrows(ApiException.class,()->NoteRangeSupport.validate(source(),1L,
        List.of(new NoteRange(10,0,15),new NoteRange(30,0,4))));
    assertThrows(ApiException.class,()->NoteRangeSupport.validate(source(),1L,
        List.of(new NoteRange(10,0,5),new NoteRange(20,0,3))));
    assertThrows(ApiException.class,()->NoteRangeSupport.validate(source(),1L,
        List.of(new NoteRange(30,0,4),new NoteRange(20,0,6))));
    assertThrows(ApiException.class,()->NoteRangeSupport.validate(source(),1L,
        List.of(new NoteRange(10,0,99))));
  }
  @Test void keepsEmptyMiddleParagraphButRejectsSelectionFromAnotherBook() {
    var repository=mock(BookParagraphRepository.class);
    when(repository.findByBookIdOrderByParagraphOrderAsc(1L)).thenReturn(List.of(
        paragraph(1,"A"),paragraph(2,""),paragraph(3,"B")));
    assertEquals("A\n\n\n\nB",NoteRangeSupport.validate(repository,1L,List.of(
        new NoteRange(1,0,1),new NoteRange(2,0,0),new NoteRange(3,0,1))).text());
    assertThrows(ApiException.class,()->NoteRangeSupport.validate(repository,1L,
        List.of(new NoteRange(99,0,1))));
  }
  @Test void rejectsVeryLargeQuotesBeforeSaving() {
    var repository=mock(BookParagraphRepository.class);
    when(repository.findByBookIdOrderByParagraphOrderAsc(1L)).thenReturn(List.of(paragraph(1,"x".repeat(30001))));
    assertThrows(ApiException.class,()->NoteRangeSupport.validate(repository,1L,List.of(new NoteRange(1,0,30001))));
  }
}

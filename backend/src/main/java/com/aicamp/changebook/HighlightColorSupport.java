package com.aicamp.changebook;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.springframework.http.HttpStatus;
final class HighlightColorSupport {
 private HighlightColorSupport() {}
 private static final Map<String,String> LEGACY = Map.ofEntries(
  Map.entry("YELLOW","#FFF59D"),
  Map.entry("PINK","#F8BBD0"),
  Map.entry("GREEN","#A5D6A7"),
  Map.entry("BLUE","#90CAF9"),
  Map.entry("PURPLE","#CE93D8"),
  Map.entry("ORANGE","#FFCC80"),
  Map.entry("RED","#EF9A9A"),
  Map.entry("MINT","#80CBC4"),
  Map.entry("SKY","#B3E5FC"),
  Map.entry("GRAY","#BDBDBD"),
  Map.entry("PEACH","#FFCCBC"));
 private static final Set<String> ALLOWED = Set.copyOf(LEGACY.values());
 static String normalize(String value) {
  if(value==null)return null;
  String code=value.trim().toUpperCase(Locale.ROOT);
  code=LEGACY.getOrDefault(code,code);
  if(!ALLOWED.contains(code))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_HIGHLIGHT_COLOR","지원하지 않는 형광펜 색상입니다.");
  return code;
 }
}

package com.aicamp.changebook;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
class AiReadingService {

    private static final int MAX_SENTENCES_WITHOUT_NOTE = 40;

    private final GeminiClient geminiClient;
    private final AiReadingFriendRepository friendRepository;
    private final AiReadingNoteRepository noteRepository;
    private final BookParagraphRepository paragraphRepository;
    private final ObjectMapper objectMapper;

    private final String readingRules;


    AiReadingService(
            GeminiClient geminiClient,
            AiReadingFriendRepository friendRepository,
            AiReadingNoteRepository noteRepository,
            BookParagraphRepository paragraphRepository,
            ObjectMapper objectMapper
    ) {
        this.geminiClient = geminiClient;
        this.friendRepository = friendRepository;
        this.noteRepository = noteRepository;
        this.paragraphRepository = paragraphRepository;
        this.objectMapper = objectMapper;

        this.readingRules = loadReadingRules();
    }


    // =========================================================
    // 책 전체 읽기
    // =========================================================

    void generateNotes(Long bookId, Long friendId) {

        AiReadingFriend friend = loadFriend(friendId);

        List<BookParagraph> paragraphs =
                paragraphRepository.findByBookIdOrderByParagraphOrderAsc(bookId);


        // 지금까지 책에서 실제로 알게 된 내용
        String bookMemory = "";


        // 이 캐릭터가 지금까지 무엇에 반응했는지
        String personaMemory = "";


        // 마지막 메모 이후 지나간 문장 수
        int sentencesWithoutNote = 0;


        // 마지막 메모 이후 지나온 문단들
        List<BookParagraph> pendingParagraphs =
                new ArrayList<>();


        for (BookParagraph paragraph : paragraphs) {

            // -------------------------------------------------
            // 1. 현재 문단을 처음 읽는 순간의 반응 생성
            // -------------------------------------------------

            String response = generateForParagraph(
                    friend,
                    paragraph,
                    bookMemory,
                    personaMemory
            );

            List<GeneratedNote> generatedNotes =
                    parseGeneratedNotes(response);


            int savedCount = 0;


            for (GeneratedNote generatedNote : generatedNotes) {

                boolean saved = saveGeneratedNote(
                        bookId,
                        friend,
                        paragraph,
                        generatedNote
                );

                if (saved) {
                    savedCount++;
                }
            }


            // -------------------------------------------------
            // 2. 메모 간격 관리
            // -------------------------------------------------

            if (savedCount > 0) {

                // 자연스러운 메모가 생겼으므로 초기화
                sentencesWithoutNote = 0;
                pendingParagraphs.clear();

            } else {

                pendingParagraphs.add(paragraph);

                sentencesWithoutNote +=
                        countSentences(paragraph.content);
            }


            // -------------------------------------------------
            // 3. 약 40문장 동안 메모가 하나도 없었다면
            //    최근 범위에서 가장 자연스러운 메모 최소 1개
            // -------------------------------------------------

            if (sentencesWithoutNote >= MAX_SENTENCES_WITHOUT_NOTE
                    && !pendingParagraphs.isEmpty()) {

                String forcedResponse =
                        generateRequiredNote(
                                friend,
                                pendingParagraphs,
                                bookMemory,
                                personaMemory
                        );


                List<ForcedGeneratedNote> forcedNotes =
                        parseForcedGeneratedNotes(forcedResponse);


                boolean forcedSaved = false;


                for (ForcedGeneratedNote generated : forcedNotes) {

                    BookParagraph target =
                            findParagraph(
                                    pendingParagraphs,
                                    generated.paragraph_order()
                            );


                    if (target == null) {
                        continue;
                    }


                    GeneratedNote note =
                            new GeneratedNote(
                                    generated.anchor_text(),
                                    generated.note()
                            );


                    if (saveGeneratedNote(
                            bookId,
                            friend,
                            target,
                            note
                    )) {

                        forcedSaved = true;

                        // 최소 1개만 필요
                        break;
                    }
                }


                if (forcedSaved) {
                    sentencesWithoutNote = 0;
                    pendingParagraphs.clear();
                }
            }


            // -------------------------------------------------
            // 4. 현재 문단을 다 읽은 뒤 Book Memory 갱신
            //
            // 중요:
            // 메모 생성보다 뒤에서 실행한다.
            // 따라서 현재 문단에 반응할 때는
            // 미래 정보가 memory에 들어갈 수 없다.
            // -------------------------------------------------

            bookMemory = updateBookMemory(
                    bookMemory,
                    paragraph
            );


            // -------------------------------------------------
            // 5. 이번 문단에서 실제 저장된 메모를 이용해
            //    Persona Memory 갱신
            // -------------------------------------------------

            if (savedCount > 0) {

                personaMemory = updatePersonaMemory(
                        personaMemory,
                        generatedNotes
                );
            }
        }
    }


    // =========================================================
    // AI 친구
    // =========================================================

    private AiReadingFriend loadFriend(Long friendId) {

        return friendRepository.findById(friendId)
                .orElseThrow(() ->
                        new IllegalArgumentException(
                                "AI 독서 친구를 찾을 수 없습니다. friendId="
                                        + friendId
                        )
                );
    }


    // =========================================================
    // reading_rules.md 읽기
    // =========================================================

    private String loadReadingRules() {

        try {

            ClassPathResource resource =
                    new ClassPathResource(
                            "ai/prompts/reading_rules.md"
                    );


            try (InputStream inputStream =
                         resource.getInputStream()) {

                return new String(
                        inputStream.readAllBytes(),
                        StandardCharsets.UTF_8
                );
            }

        } catch (Exception e) {

            throw new IllegalStateException(
                    "reading_rules.md 파일을 읽을 수 없습니다.",
                    e
            );
        }
    }


    // =========================================================
    // 일반 메모 생성
    // =========================================================

    private String generateForParagraph(
            AiReadingFriend friend,
            BookParagraph paragraph,
            String bookMemory,
            String personaMemory
    ) {

        String prompt = """
                너는 책을 처음부터 순서대로 읽고 있는 AI 독서 친구다.

                아래의 공통 독서 규칙과 캐릭터 페르소나를 따른다.


                ==============================
                [공통 독서 규칙]
                ==============================

                %s


                ==============================
                [캐릭터 페르소나]
                ==============================

                %s


                ==============================
                [지금까지의 Book Memory]
                ==============================

                %s


                ==============================
                [지금까지의 Persona Memory]
                ==============================

                %s


                ==============================
                [현재 문단]
                ==============================

                %s


                현재 문단을 처음 읽는 순간의 반응만 생성한다.

                Book Memory와 Persona Memory는
                이전까지 읽은 내용을 기억하기 위한 참고 정보다.

                memory에 있다는 이유만으로
                과거 내용에 새 메모를 만들지 마라.

                현재 문단에서 자연스럽게 반응할 부분이 없다면
                반드시 []만 출력한다.
                """.formatted(
                readingRules,
                friend.persona,
                emptyMemory(bookMemory),
                emptyMemory(personaMemory),
                paragraph.content
        );


        return geminiClient.generate(prompt);
    }


    // =========================================================
    // 40문장 강제 메모
    // =========================================================

    private String generateRequiredNote(
            AiReadingFriend friend,
            List<BookParagraph> paragraphs,
            String bookMemory,
            String personaMemory
    ) {

        StringBuilder text = new StringBuilder();


        for (BookParagraph paragraph : paragraphs) {

            text.append("\n")
                    .append("[paragraph_order=")
                    .append(paragraph.paragraphOrder)
                    .append("]\n")
                    .append(paragraph.content)
                    .append("\n");
        }


        String prompt = """
                너는 책을 처음부터 순서대로 읽고 있는 AI 독서 친구다.

                아래 범위까지 읽는 동안 아직 메모를 하나도 남기지 않았다.

                공통 독서 규칙상 약 40문장 동안에는
                최소 하나의 메모가 필요하다.

                따라서 아래 제공된 범위에서
                이 캐릭터가 가장 자연스럽게 반응했을 법한 부분 하나를 고른다.

                억지로 거창한 의미를 만들지 않는다.


                ==============================
                [공통 독서 규칙]
                ==============================

                %s


                ==============================
                [캐릭터 페르소나]
                ==============================

                %s


                ==============================
                [이 범위를 읽기 전의 Book Memory]
                ==============================

                %s


                ==============================
                [Persona Memory]
                ==============================

                %s


                ==============================
                [메모가 없었던 최근 본문]
                ==============================

                %s


                반드시 다음 JSON 배열 형식으로만 응답한다.

                [
                  {
                    "paragraph_order": 123,
                    "anchor_text": "해당 문단에 실제로 존재하는 문구",
                    "note": "캐릭터가 남긴 메모"
                  }
                ]

                paragraph_order는 반드시 위 본문에 표시된
                실제 paragraph_order 중 하나를 사용한다.

                anchor_text는 해당 문단의 원문을
                글자 그대로 가져온다.

                최소 1개의 메모를 생성한다.

                JSON 외의 설명이나 마크다운은 출력하지 않는다.
                """.formatted(
                readingRules,
                friend.persona,
                emptyMemory(bookMemory),
                emptyMemory(personaMemory),
                text
        );


        return geminiClient.generate(prompt);
    }


    // =========================================================
    // Book Memory 업데이트
    // =========================================================

    private String updateBookMemory(
            String currentMemory,
            BookParagraph paragraph
    ) {

        String prompt = """
                책을 순서대로 읽으면서 유지하는
                객관적인 Book Memory를 업데이트한다.

                Book Memory에는 독자가 지금까지 실제로 알게 된
                사건, 인물, 관계, 장소, 중요한 사실만 간결하게 남긴다.

                해석이나 감상은 넣지 않는다.

                아직 확실하지 않은 내용을 사실처럼 단정하지 않는다.

                꿈, 상상, 회상, 추측, 이야기 속 이야기 등은
                실제 현재 사건과 구분해서 기록한다.

                앞으로 나올 내용을 추측하거나 추가하지 않는다.

                너무 길어지지 않도록
                중요하지 않은 세부사항은 정리한다.


                [기존 Book Memory]

                %s


                [방금 읽은 문단]

                %s


                업데이트된 Book Memory만 출력한다.
                설명이나 제목은 붙이지 않는다.
                """.formatted(
                emptyMemory(currentMemory),
                paragraph.content
        );


        return geminiClient.generate(prompt).trim();
    }


    // =========================================================
    // Persona Memory 업데이트
    // =========================================================

    private String updatePersonaMemory(
            String currentMemory,
            List<GeneratedNote> notes
    ) {

        StringBuilder newNotes = new StringBuilder();


        for (GeneratedNote note : notes) {

            if (note.note() == null || note.note().isBlank()) {
                continue;
            }

            newNotes.append("- ")
                    .append(note.note())
                    .append("\n");
        }


        if (newNotes.isEmpty()) {
            return currentMemory;
        }


        String prompt = """
                한 캐릭터가 책을 읽으면서 지금까지
                무엇에 관심을 보였고 어떤 생각이나 감정을 가졌는지
                기억하기 위한 Persona Memory를 업데이트한다.

                캐릭터의 모든 메모를 그대로 저장하지 않는다.

                나중의 독서 반응에 실제로 영향을 줄 만한
                관심, 생각, 감정, 의문, 인물에 대한 인상만 간결하게 남긴다.

                캐릭터가 말하지 않은 생각을 새로 만들어내지 않는다.

                너무 길어지지 않도록 기존 내용을 정리하거나 합칠 수 있다.


                [기존 Persona Memory]

                %s


                [이번에 남긴 메모]

                %s


                업데이트된 Persona Memory만 출력한다.
                설명이나 제목은 붙이지 않는다.
                """.formatted(
                emptyMemory(currentMemory),
                newNotes
        );


        return geminiClient.generate(prompt).trim();
    }


    // =========================================================
    // 일반 Gemini JSON 파싱
    // =========================================================

    private List<GeneratedNote> parseGeneratedNotes(
            String response
    ) {

        try {

            return objectMapper.readValue(
                    response,
                    objectMapper.getTypeFactory()
                            .constructCollectionType(
                                    List.class,
                                    GeneratedNote.class
                            )
            );

        } catch (Exception e) {

            System.out.println(
                    "Gemini 메모 JSON 파싱 실패: "
                            + response
            );

            return List.of();
        }
    }


    // =========================================================
    // 강제 메모 JSON 파싱
    // =========================================================

    private List<ForcedGeneratedNote> parseForcedGeneratedNotes(
            String response
    ) {

        try {

            return objectMapper.readValue(
                    response,
                    objectMapper.getTypeFactory()
                            .constructCollectionType(
                                    List.class,
                                    ForcedGeneratedNote.class
                            )
            );

        } catch (Exception e) {

            System.out.println(
                    "Gemini 강제 메모 JSON 파싱 실패: "
                            + response
            );

            return List.of();
        }
    }


    // =========================================================
    // anchor 검증 + DB 저장
    // =========================================================

    private boolean saveGeneratedNote(
            Long bookId,
            AiReadingFriend friend,
            BookParagraph paragraph,
            GeneratedNote generatedNote
    ) {

        if (generatedNote.anchor_text() == null
                || generatedNote.anchor_text().isBlank()) {

            return false;
        }


        if (generatedNote.note() == null
                || generatedNote.note().isBlank()) {

            return false;
        }


        String anchorText =
                generatedNote.anchor_text();


        int startOffset =
                paragraph.content.indexOf(anchorText);


        // Gemini가 원문에 없는 문구를 만들었다면 저장하지 않음
        if (startOffset < 0) {

            System.out.println(
                    "원문에서 찾을 수 없는 anchor: "
                            + anchorText
            );

            return false;
        }


        int endOffset =
                startOffset + anchorText.length();


        AiReadingNote note =
                new AiReadingNote();


        note.friendId = friend.id;
        note.bookId = bookId;

        note.paragraphOrder =
                paragraph.paragraphOrder;

        note.startOffset =
                startOffset;

        note.endOffset =
                endOffset;

        note.selectedText =
                anchorText;

        note.content =
                generatedNote.note();

        note.createdAt =
                OffsetDateTime.now();


        noteRepository.save(note);


        return true;
    }


    // =========================================================
    // paragraphOrder로 원래 문단 찾기
    // =========================================================

    private BookParagraph findParagraph(
            List<BookParagraph> paragraphs,
            Integer paragraphOrder
    ) {

        if (paragraphOrder == null) {
            return null;
        }


        for (BookParagraph paragraph : paragraphs) {

            if (paragraph.paragraphOrder.equals(paragraphOrder)) {
                return paragraph;
            }
        }


        return null;
    }


    // =========================================================
    // 대략적인 문장 수 계산
    // =========================================================

    private int countSentences(String text) {

        if (text == null || text.isBlank()) {
            return 0;
        }


        int count = 0;


        for (int i = 0; i < text.length(); i++) {

            char c = text.charAt(i);

            if (c == '.'
                    || c == '?'
                    || c == '!'
                    || c == '。'
                    || c == '？'
                    || c == '！') {

                count++;
            }
        }


        // 문장부호가 없는 짧은 문단도
        // 최소 한 문장으로 취급
        return Math.max(count, 1);
    }


    // =========================================================
    // 비어 있는 memory 표시
    // =========================================================

    private String emptyMemory(String memory) {

        if (memory == null || memory.isBlank()) {
            return "(아직 없음)";
        }

        return memory;
    }


    // =========================================================
    // Gemini 응답 구조
    // =========================================================

    private record GeneratedNote(
            String anchor_text,
            String note
    ) {
    }


    private record ForcedGeneratedNote(
            Integer paragraph_order,
            String anchor_text,
            String note
    ) {
    }
}
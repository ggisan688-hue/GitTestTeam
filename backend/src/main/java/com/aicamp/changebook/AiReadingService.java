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

    private static final int MAX_SENTENCES_WITHOUT_NOTE = 12;

    private final GeminiClient geminiClient;
    private final AiReadingFriendRepository friendRepository;
    private final AiReadingNoteRepository noteRepository;
private final AiReadingProgressRepository progressRepository;
private final BookParagraphRepository paragraphRepository;
private final ObjectMapper objectMapper;

    private final String readingRules;


    AiReadingService(
        GeminiClient geminiClient,
        AiReadingFriendRepository friendRepository,
        AiReadingNoteRepository noteRepository,
        AiReadingProgressRepository progressRepository,
        BookParagraphRepository paragraphRepository,
        ObjectMapper objectMapper
) {
    this.geminiClient = geminiClient;
    this.friendRepository = friendRepository;
    this.noteRepository = noteRepository;
    this.progressRepository = progressRepository;
    this.paragraphRepository = paragraphRepository;
    this.objectMapper = objectMapper;

    this.readingRules = loadReadingRules();
}


    // =========================================================
    // 책 전체 읽기
    // =========================================================

    void generateNotes(Long bookId, Long friendId) {

    AiReadingFriend friend = loadFriend(friendId);

    List<BookParagraph> allParagraphs =
            paragraphRepository.findByBookIdOrderByParagraphOrderAsc(bookId);

    System.out.println("===== AI 독서 시작 =====");
    System.out.println("bookId = " + bookId);
    System.out.println("전체 문단 수 = " + allParagraphs.size());

    if (allParagraphs.isEmpty()) {
        return;
    }

    AiReadingProgress progress =
            progressRepository
                    .findByFriendIdAndBookId(friendId, bookId)
                    .orElseGet(() -> {
                        AiReadingProgress newProgress =
                                new AiReadingProgress();

                        newProgress.friendId = friendId;
                        newProgress.bookId = bookId;
                        newProgress.lastParagraphOrder = 0;
                        newProgress.bookMemory = "";
                        newProgress.personaMemory = "";
                        newProgress.completed = false;
                        newProgress.updatedAt =
                                java.time.OffsetDateTime.now();

                        return progressRepository.save(newProgress);
                    });

    // 이미 끝까지 읽은 책이면 Gemini를 다시 호출하지 않는다.
    if (progress.completed) {
        System.out.println("이미 AI 독서가 완료된 책입니다.");
        return;
    }

    int lastParagraphOrder =
            progress.lastParagraphOrder == null
                    ? 0
                    : progress.lastParagraphOrder;

    String bookMemory =
            progress.bookMemory == null
                    ? ""
                    : progress.bookMemory;

    String personaMemory =
            progress.personaMemory == null
                    ? ""
                    : progress.personaMemory;

    // 마지막으로 완료한 문단 다음부터 이어서 읽는다.
    List<BookParagraph> paragraphs =
            allParagraphs.stream()
                    .filter(paragraph ->
                            paragraph.paragraphOrder > lastParagraphOrder
                    )
                    .toList();

    if (paragraphs.isEmpty()) {
        progress.completed = true;
        progress.updatedAt =
                java.time.OffsetDateTime.now();

        progressRepository.save(progress);

        System.out.println("===== AI 독서 완료 =====");
        return;
    }

    System.out.println(
            "이어읽기 시작 paragraph = " +
                    paragraphs.get(0).paragraphOrder
    );

    System.out.println(
            "마지막 paragraph = " +
                    paragraphs.get(paragraphs.size() - 1).paragraphOrder
    );

    List<List<BookParagraph>> readingChunks =
            splitIntoReadingChunks(paragraphs);

    System.out.println(
            "남은 AI 독서 묶음 수 = " +
                    readingChunks.size()
    );

    for (int i = 0; i < readingChunks.size(); i++) {

        List<BookParagraph> chunk =
                readingChunks.get(i);

        System.out.println(
                "AI 독서 묶음 " +
                        (i + 1) +
                        "/" +
                        readingChunks.size() +
                        " : paragraph " +
                        chunk.get(0).paragraphOrder +
                        " ~ " +
                        chunk.get(chunk.size() - 1).paragraphOrder
        );

        String response = generateForChunk(
                friend,
                chunk,
                bookMemory,
                personaMemory
        );

        ChunkResponse result =
                parseChunkResponse(response);

        /*
         * 중요:
         * 파싱에 실패했는데 다음 묶음으로 넘어가면
         * 중간 내용을 건너뛸 수 있다.
         *
         * 따라서 여기서 독서를 중단한다.
         * 다음 generate 요청 때 이 묶음부터 다시 시작한다.
         */
        if (result == null) {
            System.out.println(
                    "AI 독서 묶음 응답 파싱 실패 - 현재 위치에서 중단"
            );
            return;
        }

        List<GeneratedChunkNote> generatedNotes =
                result.notes() == null
                        ? List.of()
                        : result.notes();

        int savedCount = 0;

        for (GeneratedChunkNote generated : generatedNotes) {

            BookParagraph paragraph =
                    findParagraph(
                            chunk,
                            generated.paragraph_order()
                    );

            if (paragraph == null) {
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
                    paragraph,
                    note
            )) {
                savedCount++;
            }
        }

        if (result.book_memory() != null
                && !result.book_memory().isBlank()) {

            bookMemory =
                    result.book_memory().trim();
        }

        if (!generatedNotes.isEmpty()) {

            StringBuilder updatedPersonaMemory =
                    new StringBuilder(personaMemory);

            for (GeneratedChunkNote generated : generatedNotes) {

                if (generated.note() == null
                        || generated.note().isBlank()) {
                    continue;
                }

                if (!updatedPersonaMemory.isEmpty()) {
                    updatedPersonaMemory.append("\n");
                }

                updatedPersonaMemory
                        .append("- ")
                        .append(generated.note().trim());
            }

            personaMemory =
                    updatedPersonaMemory.toString();
        }

        /*
         * 이 묶음 처리가 끝난 뒤에만 진행 위치를 저장한다.
         *
         * 서버가 다음 묶음에서 꺼져도
         * 여기까지의 위치와 기억은 DB에 남는다.
         */
        progress.lastParagraphOrder =
                chunk.get(chunk.size() - 1).paragraphOrder;

        progress.bookMemory = bookMemory;
        progress.personaMemory = personaMemory;
        progress.updatedAt =
                java.time.OffsetDateTime.now();

        progressRepository.save(progress);

        System.out.println(
                "저장된 AI 메모 = " + savedCount
        );

        System.out.println(
                "AI 독서 진행 위치 저장 = paragraph " +
                        progress.lastParagraphOrder
        );
    }

    // 모든 묶음을 정상적으로 통과했을 때만 완료 처리
    progress.completed = true;
    progress.updatedAt =
            java.time.OffsetDateTime.now();

    progressRepository.save(progress);

    System.out.println("===== AI 독서 완료 =====");
}

private List<List<BookParagraph>> splitIntoReadingChunks(
        List<BookParagraph> paragraphs
) {

    int targetCharacters = 8000;

    List<List<BookParagraph>> chunks =
            new ArrayList<>();

    List<BookParagraph> current =
            new ArrayList<>();

    int currentCharacters = 0;

    for (BookParagraph paragraph : paragraphs) {

        String content =
                paragraph.content == null
                        ? ""
                        : paragraph.content;

        if (!current.isEmpty()
                && currentCharacters + content.length()
                > targetCharacters) {

            chunks.add(new ArrayList<>(current));

            current.clear();
            currentCharacters = 0;
        }

        current.add(paragraph);

        currentCharacters +=
                content.length();
    }

    if (!current.isEmpty()) {
        chunks.add(new ArrayList<>(current));
    }

    return chunks;
}

private String generateForChunk(
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

            지금 제공되는 본문은
            네가 현재 처음 읽고 있는 범위다.

            이 범위 뒤에 어떤 내용이 나오는지는 전혀 알 수 없다.
            앞으로의 사건, 결말, 설정을 추측해서 사실처럼 사용하지 마라.

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
            [이 범위를 읽기 전의 Persona Memory]
            ==============================

            %s

            ==============================
            [지금 처음 읽는 본문]
            ==============================

            %s


            ==============================
            [메모 행동]
            ==============================

            이 본문을 실제로 처음 읽는 사람처럼 자연스럽게 읽어라.

            중요한 문장을 찾아 분석하는 것이 목적이 아니다.
            책을 읽다가 이 캐릭터라면 실제로 말하고 싶어질 만한
            순간에만 메모를 남긴다.

            예를 들어 웃기거나,
            황당하거나,
            놀랍거나,
            어이없거나,
            궁금하거나,
            긴장되거나,
            마음에 걸리거나,
            공감되거나,
            인물의 말이나 행동에 한마디 하고 싶은 순간 등이 있다.

            이것은 예시일 뿐이다.
            캐릭터의 성격과 취향에 따라 자연스럽게 반응한다.

            메모 개수를 미리 정하지 마라.

            반응할 곳이 없다면 0개여도 된다.
            한 군데만 반응하고 싶다면 1개만 남긴다.
            여러 군데에서 자연스럽게 반응한다면 여러 개를 남긴다.

            메모 수를 맞추기 위해 억지로 반응하지 마라.

            반대로 자연스럽게 여러 번 반응하고 싶은 본문인데
            일부러 하나만 고르지도 마라.

            메모는 독후감이나 줄거리 요약이 아니다.
        독자에게 장면의 의미를 설명하거나 해설하기 위한 글을 만들지 마라.

        책을 먼저 읽고 간 친구가
        책 여백에 자기 생각을 바로 적어둔 것처럼 행동한다.

        먼저 이 캐릭터로서 본문을 읽고,
        그 순간 실제로 떠오른 반응을 짧게 적는다.

        캐릭터의 말투를 강하게 유지한다.

        캐릭터의 성격이나 말투 설정과 관계없이
        "존나" 같은 강한 비속어와,
        강조를 위해 "개-"를 접두사처럼 붙이는 표현
        (예: "개에바", "개웃김", "개빡침")은 사용하지 않는다.

        단, "개판"처럼 그 자체로 자연스럽게 쓰이는 하나의 단어나
        캐릭터 고유의 다른 말투와 표현까지 순화하지는 않는다.

            Book Memory는 지금까지 실제로 읽어서 알게 된
            내용만 참고하기 위한 것이다.

            Persona Memory는 이 캐릭터가 앞에서 무엇에 관심을 보였고
            어떤 생각이나 감정을 가졌는지 이어가기 위한 것이다.

            과거 Memory에 있다는 이유만으로
            과거 장면에 새 메모를 만들지 마라.

            메모의 anchor_text는 반드시
            현재 제공된 본문에 실제로 존재하는 문구를
            글자 그대로 가져온다.


            ==============================
            [Memory 업데이트]
            ==============================

            이번 범위를 다 읽은 뒤의 Book Memory도 함께 만든다.

            Book Memory에는 지금까지 독자가 실제로 알게 된
            사건, 인물, 관계, 장소, 중요한 사실만 간결하게 유지한다.

            아직 밝혀지지 않은 내용을 사실처럼 만들지 마라.
            미래 내용을 추가하지 마라.


            ==============================
            [응답 형식]
            ==============================

            반드시 JSON 하나만 출력한다.

            {
                "notes": [
                {
                "paragraph_order": 123,
                "anchor_text": "현재 본문에 실제로 존재하는 문구",
                "note": "캐릭터가 실제로 남긴 짧고 자연스러운 메모"
                }
                ],
                "book_memory": "이번 범위까지 읽은 뒤의 Book Memory"
        }

            메모가 하나도 없다면 notes는 []로 출력한다.

            paragraph_order는 반드시 현재 제공된 본문에 표시된
            실제 paragraph_order를 사용한다.

            JSON 이외의 설명이나 마크다운은 절대 출력하지 않는다.
            """.formatted(
            readingRules,
            friend.persona,
            emptyMemory(bookMemory),
            emptyMemory(personaMemory),
            text
    );

    return geminiClient.generate(prompt);
}

private ChunkResponse parseChunkResponse(
        String response
) {

    try {

        return objectMapper.readValue(
                response,
                ChunkResponse.class
        );

    } catch (Exception e) {

        System.out.println(
                "Gemini 독서 묶음 JSON 파싱 실패: "
                        + response
        );

        return null;
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

    private record GeneratedChunkNote(
        Integer paragraph_order,
        String anchor_text,
        String note
) {
}

private record ChunkResponse(
        List<GeneratedChunkNote> notes,
        String book_memory
) {
}
}
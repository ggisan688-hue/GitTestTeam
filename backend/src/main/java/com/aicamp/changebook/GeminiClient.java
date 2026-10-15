package com.aicamp.changebook;

import com.google.genai.Client;
import com.google.genai.types.GenerateContentResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.concurrent.TimeUnit;

@Component
public class GeminiClient {

    private static final Logger log = LoggerFactory.getLogger(GeminiClient.class);
    private static final String MODEL = "gemini-3.5-flash-lite";

    private final Client client;

    public GeminiClient(@Value("${gemini.api-key:}") String apiKey) {
        this.client = apiKey == null || apiKey.isBlank()
                ? null
                : Client.builder().apiKey(apiKey).build();
    }

    public String generate(String prompt) {
        if (client == null) {
            throw new ApiException(
                    org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE,
                    "AI_SERVICE_NOT_CONFIGURED",
                    "AI 독서 친구는 현재 설정되어 있지 않습니다."
            );
        }
        long started = System.nanoTime();
        GenerateContentResponse response =
                client.models.generateContent(
                        MODEL,
                        prompt,
                        null
                );

        long elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started);
        // Usage is returned with the generation response; no additional API call.
        // Missing fields stay unknown rather than being reported as zero usage.
        if (response.usageMetadata().isPresent()) {
            var usage = response.usageMetadata().get();
            log.info("Gemini 사용량 model={} 소요시간Ms={} 입력토큰={} 출력토큰={} 생각토큰={} 캐시입력토큰={} 전체토큰={}",
                    MODEL, elapsedMs,
                    usage.promptTokenCount().map(String::valueOf).orElse("미제공"),
                    usage.candidatesTokenCount().map(String::valueOf).orElse("미제공"),
                    usage.thoughtsTokenCount().map(String::valueOf).orElse("미제공"),
                    usage.cachedContentTokenCount().map(String::valueOf).orElse("미제공"),
                    usage.totalTokenCount().map(String::valueOf).orElse("미제공"));
        } else {
            log.info("Gemini 사용량 model={} 소요시간Ms={} 토큰정보=미제공", MODEL, elapsedMs);
        }
        return response.text();
    }
}

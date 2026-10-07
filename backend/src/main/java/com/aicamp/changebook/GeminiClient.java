package com.aicamp.changebook;

import com.google.genai.Client;
import com.google.genai.types.GenerateContentResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class GeminiClient {

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
        GenerateContentResponse response =
                client.models.generateContent(
                        "gemini-3.5-flash-lite",
                        prompt,
                        null
                );

        return response.text();
    }
}

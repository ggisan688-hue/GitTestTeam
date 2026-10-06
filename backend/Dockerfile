FROM gradle:9.3.1-jdk17 AS build
WORKDIR /workspace
COPY gradlew gradlew.bat build.gradle settings.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew
COPY src ./src
RUN ./gradlew bootJar --no-daemon

FROM eclipse-temurin:17-jre
RUN addgroup --system changebook && adduser --system --ingroup changebook changebook
WORKDIR /app
COPY --from=build /workspace/build/libs/*.jar /app/changebook.jar
USER changebook
EXPOSE 8088
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/changebook.jar"]

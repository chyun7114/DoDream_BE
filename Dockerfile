# syntax=docker/dockerfile:1.7

FROM eclipse-temurin:21-jdk-jammy AS build
WORKDIR /workspace

# Gradle wrapper and build scripts first for layer caching
COPY gradlew gradlew.bat settings.gradle build.gradle ./
COPY gradle ./gradle

RUN chmod +x gradlew
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew --no-daemon help

# Application sources
COPY src ./src

# Build jar with cached Gradle dependencies
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew --no-daemon bootJar -x test

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

ARG PROFILE=main
ENV SPRING_PROFILES_ACTIVE=${PROFILE}

COPY --from=build /workspace/build/libs/*.jar /app/app.jar

ENTRYPOINT ["java", "-jar", "/app/app.jar"]

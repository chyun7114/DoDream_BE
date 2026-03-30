FROM eclipse-temurin:21-jre-jammy

ARG JAR_FILE=build/libs/*.jar

COPY ${JAR_FILE} app.jar
ARG PROFILE=main
ENV SPRING_PROFILES_ACTIVE=${PROFILE}

ENTRYPOINT ["java", "-jar", "/app.jar"]

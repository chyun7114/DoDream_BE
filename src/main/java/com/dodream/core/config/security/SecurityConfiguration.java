package com.dodream.core.config.security;

import com.dodream.core.infrastructure.filter.ExceptionHandlerFilter;
import com.dodream.core.infrastructure.filter.JwtAuthenticationFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfigurationSource;

@Configuration
@RequiredArgsConstructor
public class SecurityConfiguration {

    private final CorsConfigurationSource corsConfigurationSource;
    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final ExceptionHandlerFilter exceptionHandlerFilter;

    private static final String[] WHITELIST = {
        "/v3/api-docs/**",
        "/swagger-ui/**",
        "/swagger-ui.html",
        "/test/**",
        "/v1/recruit/**",
        "/v1/ncs/**",
        "/v1/training/**",
        "/v1/region/**",
        "/v1/member/auth/sign-up",
        "/v1/member/auth/check-id/**",
        "/v1/member/auth/check-nickname/**",
        "/v1/member/auth/login",
        "/v1/member/auth/email/**",
        "/v1/clova/**",
        "/v1/job/**",
        "/v1/todo/other/public",
        "/v1/job/todo/**",
        "/v1/community/**",
        "/v1/todo/popular",
        "/v1/todo/floating/popular",
        "/actuator/**"
    };

    @Bean
    public BCryptPasswordEncoder bCryptPasswordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf((csrfConfig) ->
                csrfConfig.disable()
            )
            .cors(cors -> cors.configurationSource(corsConfigurationSource))
            .headers((headerConfig) ->
                headerConfig.frameOptions(frameOptionsConfig ->
                    frameOptionsConfig.disable()
                )
            )
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(WHITELIST).permitAll()
                .anyRequest().authenticated()
            )
            .addFilterBefore(
                exceptionHandlerFilter, UsernamePasswordAuthenticationFilter.class
            )
            .addFilterBefore(
                jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class
            );

        return http.build();
    }
}

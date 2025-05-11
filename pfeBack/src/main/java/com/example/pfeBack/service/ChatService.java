package com.example.pfeBack.service;

import com.example.pfeBack.dto.OpenRouterRequest;
import com.example.pfeBack.dto.OpenRouterResponse;
import com.example.pfeBack.model.MachineFailure;
import com.example.pfeBack.model.DefectType;
import com.example.pfeBack.model.MonthlyPerformance;
import com.example.pfeBack.model.User;
import com.example.pfeBack.model.OrderReference;
import com.example.pfeBack.model.Performance;
import com.example.pfeBack.repository.MachineFailureRepository;
import com.example.pfeBack.repository.DefectTypeRepository;
import com.example.pfeBack.repository.MonthlyPerformanceRepository;
import com.example.pfeBack.repository.UserRepository;
import com.example.pfeBack.repository.OrderReferenceRepository;
import com.example.pfeBack.repository.PerformanceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
@RequiredArgsConstructor
@Slf4j
public class ChatService {

    private final WebClient openRouterWebClient;
    private final MachineFailureRepository machineFailureRepository;
    private final DefectTypeRepository defectTypeRepository;
    private final MonthlyPerformanceRepository monthlyPerformanceRepository;
    private final UserRepository userRepository;
    private final OrderReferenceRepository orderReferenceRepository;
    private final PerformanceRepository performanceRepository;

    public Mono<String> getChatResponse(String question) {
        String lowerQ = question.toLowerCase();
        String context = null;

        // 1. Handle target/performance for a specific date and orderRef
        if ((lowerQ.contains("target") || lowerQ.contains("performance")) && (lowerQ.contains("orderref") || lowerQ.contains("order ref"))) {
            String date = extractDateFromQuestion(question);
            Integer orderRef = extractOrderRefFromQuestion(question);
            if (date != null && orderRef != null) {
                var performances = performanceRepository.findByOrderRefAndDate(orderRef, date);
                if (!performances.isEmpty()) {
                    var perf = performances.get(0);
                    context = String.format("The production target for orderRef %d on %s is %d.", orderRef, date, perf.getProductionTarget());
                } else {
                    context = String.format("No performance data found for orderRef %d on %s.", orderRef, date);
                }
            }
        }

        // 2. Multi-term flexible search for all collections
        if (context == null) {
            MultiSearchTerms terms = extractMultiSearchTerms(question);
            // Performance: match all terms (date, workshop, chain, etc.)
            var perfMatches = performanceRepository.findAll().stream()
                .filter(p -> (terms.date == null || (p.getDate() != null && p.getDate().equalsIgnoreCase(terms.date)))
                        && (terms.workshop == null || (p.getWorkshop() != null && p.getWorkshop().toLowerCase().contains(terms.workshop)))
                        && (terms.chain == null || (p.getChain() != null && p.getChain().toLowerCase().contains(terms.chain)))
                        && (terms.orderRef == null || (p.getOrderRef() != null && p.getOrderRef().toString().equals(terms.orderRef)))
                ).collect(Collectors.toList());
            if (!perfMatches.isEmpty()) {
                var p = perfMatches.get(0);
                context = String.format("Performance for workshop '%s', chain '%s', supervisor '%s', date %s: produced %d, target %d, defects %d, orderRef %s.",
                        p.getWorkshop(), p.getChain(), p.getSupervisorId(), p.getDate(), p.getProduced(), p.getProductionTarget(), p.getDefects(), p.getOrderRef());
            }
            // MachineFailure: match all terms (date, machineReference, technician, etc.)
            if (context == null) {
                var machineMatches = machineFailureRepository.findAll().stream()
                    .filter(m -> (terms.date == null || (m.getDate() != null && m.getDate().equalsIgnoreCase(terms.date)))
                            && (terms.machineReference == null || (m.getMachineReference() != null && m.getMachineReference().toLowerCase().contains(terms.machineReference)))
                            && (terms.technician == null || (m.getTechnician_name() != null && m.getTechnician_name().toLowerCase().contains(terms.technician)))
                    ).collect(Collectors.toList());
                if (!machineMatches.isEmpty()) {
                    var m = machineMatches.get(0);
                    context = String.format("Machine failure for reference '%s', date %s: %s (by %s, %d min)",
                            m.getMachineReference(), m.getDate(), m.getDescription(), m.getTechnician_name(), m.getTimeSpent());
                }
            }
            // OrderReference: match all terms (orderRef only)
            if (context == null) {
                var orderMatches = orderReferenceRepository.findAll().stream()
                    .filter(o -> (terms.orderRef == null || (o.getOrderRef() != null && o.getOrderRef().toString().equals(terms.orderRef)))
                    ).collect(Collectors.toList());
                if (!orderMatches.isEmpty()) {
                    var o = orderMatches.get(0);
                    context = String.format("OrderRef: %s, Target: %s.", o.getOrderRef(), o.getProductionTarget());
                }
            }
            // DefectType: match all terms (defectName)
            if (context == null) {
                var defectMatches = defectTypeRepository.findAll().stream()
                    .filter(d -> (terms.defectName == null || (d.getDefectName() != null && d.getDefectName().toLowerCase().contains(terms.defectName))))
                    .collect(Collectors.toList());
                if (!defectMatches.isEmpty()) {
                    var d = defectMatches.get(0);
                    context = String.format("Defect type '%s' found with id %s.", d.getDefectName(), d.getId());
                }
            }
            // MonthlyPerformance: match all terms (month, orderRef)
            if (context == null) {
                var monthlyMatches = monthlyPerformanceRepository.findAll().stream()
                    .filter(mp -> (terms.month == null || (mp.getMonth() != null && mp.getMonth().equalsIgnoreCase(terms.month)))
                            && (terms.orderRef == null || (mp.getOrderRef() != null && mp.getOrderRef().equals(terms.orderRef)))
                    ).collect(Collectors.toList());
                if (!monthlyMatches.isEmpty()) {
                    var mp = monthlyMatches.get(0);
                    context = String.format("Monthly performance for orderRef '%s', month %s: produced %d, target %d, defects %d.",
                            mp.getOrderRef(), mp.getMonth(), mp.getProduced(), mp.getProductionTarget(), mp.getDefects());
                }
            }
            // If still not found
            if (context == null && (terms.hasAny())) {
                context = "No matching data found for your search terms in the database.";
            }
        }

        // Smart field-matching for each collection
        if (context == null) {
            // Machine failures
            if (lowerQ.contains("machine failure") || lowerQ.contains("machine stopped") || lowerQ.contains("intervention")) {
                List<MachineFailure> failures = machineFailureRepository.findAll();
                if (lowerQ.contains("technician")) {
                    context = "Machine failures (technician info):\n" + failures.stream().limit(10).map(f ->
                        String.format("- %s: %s (by %s)", f.getDate(), f.getDescription(), f.getTechnician_name())
                    ).collect(Collectors.joining("\n"));
                } else if (lowerQ.contains("time")) {
                    context = "Machine failures (time spent):\n" + failures.stream().limit(10).map(f ->
                        String.format("- %s: %d min on %s", f.getDate(), f.getTimeSpent(), f.getMachineReference())
                    ).collect(Collectors.joining("\n"));
                } else if (lowerQ.contains("machine") || lowerQ.contains("reference")) {
                    context = "Machine failures (machine reference):\n" + failures.stream().limit(10).map(f ->
                        String.format("- %s: %s", f.getDate(), f.getMachineReference())
                    ).collect(Collectors.joining("\n"));
                } else {
                    context = "Recent machine failures:\n" + failures.stream().limit(10).map(f ->
                        String.format("- [%s] %s: %s (by %s)", f.getDate(), f.getMachineReference(), f.getDescription(), f.getTechnician_name())
                    ).collect(Collectors.joining("\n"));
                }
            } else if (lowerQ.contains("defect")) {
                List<DefectType> defects = defectTypeRepository.findAll();
                context = "Defect types:\n" + defects.stream().limit(10).map(d ->
                        String.format("- %s: %s", d.getId(), d.getDefectName())
                ).collect(Collectors.joining("\n"));
            } else if (lowerQ.contains("monthly performance") || lowerQ.contains("monthly")) {
                List<MonthlyPerformance> perf = monthlyPerformanceRepository.findAll();
                if (lowerQ.contains("defect")) {
                    context = "Monthly performance (defects):\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s: %d defects (OrderRef: %s)", p.getMonth(), p.getDefects(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                } else if (lowerQ.contains("produced")) {
                    context = "Monthly performance (produced):\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s: %d produced (OrderRef: %s)", p.getMonth(), p.getProduced(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                } else if (lowerQ.contains("target")) {
                    context = "Monthly performance (target):\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s: target %d (OrderRef: %s)", p.getMonth(), p.getProductionTarget(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                } else {
                    context = "Monthly performance:\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s (OrderRef: %s)", p.getMonth(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                }
            } else if (lowerQ.contains("order reference") || lowerQ.contains("orderref") || lowerQ.contains("order ref")) {
                List<OrderReference> orders = orderReferenceRepository.findAll();
                context = "Order references (orderRef, target):\n" + orders.stream().limit(10).map(o ->
                    String.format("- %s: target %s", o.getOrderRef(), o.getProductionTarget())
                ).collect(Collectors.joining("\n"));
            } else if (lowerQ.contains("performance") || lowerQ.contains("produced") || lowerQ.contains("target")) {
                List<Performance> perf = performanceRepository.findAll();
                if (lowerQ.contains("defect")) {
                    context = "Performance (defects):\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s: %d defects (OrderRef: %s)", p.getDate(), p.getDefects(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                } else if (lowerQ.contains("produced")) {
                    context = "Performance (produced):\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s: %d produced (OrderRef: %s)", p.getDate(), p.getProduced(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                } else if (lowerQ.contains("target")) {
                    context = "Performance (target):\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s: target %d (OrderRef: %s)", p.getDate(), p.getProductionTarget(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                } else {
                    context = "Performance:\n" + perf.stream().limit(10).map(p ->
                        String.format("- %s (OrderRef: %s)", p.getDate(), p.getOrderRef())
                    ).collect(Collectors.joining("\n"));
                }
            }
        }

        if (context == null) {
            return Mono.just("I can only answer questions about machine failures, defect types, monthly performance, order references, or performance.");
        }

        // If context is a direct answer (not a data summary), skip OpenRouter
        if (context.startsWith("The production target") || context.startsWith("No performance data")) {
            return Mono.just(context);
        }

        String prompt = context + "\n\nUser question: " + question;
        OpenRouterRequest.Message userMessage = new OpenRouterRequest.Message("user", prompt);
        OpenRouterRequest request = new OpenRouterRequest();
        request.setMessages(Collections.singletonList(userMessage));
        request.setModel("mistralai/mistral-7b-instruct:free");

        log.info("Sending request to OpenRouter: {}", request);

        return openRouterWebClient.post()
                .uri("/chat/completions")
                .bodyValue(request)
                .retrieve()
                .bodyToMono(OpenRouterResponse.class)
                .doOnNext(response -> log.info("Received response from OpenRouter: {}", response))
                .map(response -> response.getChoices().get(0).getMessage().getContent())
                .onErrorResume(e -> {
                    if (e instanceof org.springframework.web.reactive.function.client.WebClientResponseException) {
                        org.springframework.web.reactive.function.client.WebClientResponseException we = (org.springframework.web.reactive.function.client.WebClientResponseException) e;
                        log.error("Error response body: {}", we.getResponseBodyAsString());
                    } else {
                        log.error("Error calling OpenRouter API: {}", e.getMessage());
                    }
                    return Mono.just("Sorry, I encountered an error while processing your request. Please try again later.");
                });
    }

    // Helper to extract date in yyyy-MM-dd from question
    private String extractDateFromQuestion(String question) {
        Pattern pattern = Pattern.compile("(\\d{4}-\\d{2}-\\d{2})");
        Matcher matcher = pattern.matcher(question);
        if (matcher.find()) {
            return matcher.group(1);
        }
        return null;
    }

    // Helper to extract orderRef (integer) from question
    private Integer extractOrderRefFromQuestion(String question) {
        Pattern pattern = Pattern.compile("orderRef\\s*(\\d+)", Pattern.CASE_INSENSITIVE);
        Matcher matcher = pattern.matcher(question);
        if (matcher.find()) {
            return Integer.parseInt(matcher.group(1));
        }
        return null;
    }

    // Helper class for multi-term extraction
    private static class MultiSearchTerms {
        String date;
        String workshop;
        String chain;
        String orderRef;
        String machineReference;
        String technician;
        String defectName;
        String month;
        boolean hasAny() {
            return date != null || workshop != null || chain != null || orderRef != null || machineReference != null || technician != null || defectName != null || month != null;
        }
    }

    // Helper to extract multiple search terms from the question
    private MultiSearchTerms extractMultiSearchTerms(String question) {
        MultiSearchTerms terms = new MultiSearchTerms();
        // Date
        terms.date = extractDateFromQuestion(question);
        // Month (yyyy-MM)
        Pattern monthPat = Pattern.compile("(\\d{4}-\\d{2})");
        Matcher monthM = monthPat.matcher(question);
        if (monthM.find()) terms.month = monthM.group(1);
        // Workshop
        Pattern wsPat = Pattern.compile("workshop\\s*([a-zA-Z0-9]+)", Pattern.CASE_INSENSITIVE);
        Matcher wsM = wsPat.matcher(question);
        if (wsM.find()) terms.workshop = wsM.group(1).toLowerCase();
        // Chain
        Pattern chPat = Pattern.compile("chain\\s*([a-zA-Z0-9]+)", Pattern.CASE_INSENSITIVE);
        Matcher chM = chPat.matcher(question);
        if (chM.find()) terms.chain = chM.group(1).toLowerCase();
        // OrderRef
        Pattern orPat = Pattern.compile("orderRef\\s*(\\d+)", Pattern.CASE_INSENSITIVE);
        Matcher orM = orPat.matcher(question);
        if (orM.find()) terms.orderRef = orM.group(1);
        // Machine reference (W1-C2-M3 style)
        Pattern machPat = Pattern.compile("(w\\d+-c\\d+-m\\d+)", Pattern.CASE_INSENSITIVE);
        Matcher machM = machPat.matcher(question);
        if (machM.find()) terms.machineReference = machM.group(1).toLowerCase();
        // Technician
        Pattern techPat = Pattern.compile("technician\\s*([a-zA-Z0-9]+)", Pattern.CASE_INSENSITIVE);
        Matcher techM = techPat.matcher(question);
        if (techM.find()) terms.technician = techM.group(1).toLowerCase();
        // Defect name (quoted)
        Pattern defPat = Pattern.compile("defect\\s*name\\s*['\"]?([a-zA-Z0-9 ]+)['\"]?", Pattern.CASE_INSENSITIVE);
        Matcher defM = defPat.matcher(question);
        if (defM.find()) terms.defectName = defM.group(1).trim().toLowerCase();
        return terms;
    }
} 
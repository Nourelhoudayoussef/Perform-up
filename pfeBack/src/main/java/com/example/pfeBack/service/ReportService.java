package com.example.pfeBack.service;

import com.example.pfeBack.model.MachineFailure;
import com.example.pfeBack.model.Performance;
import com.example.pfeBack.repository.MachineFailureRepository;
import com.example.pfeBack.repository.PerformanceRepository;
import com.lowagie.text.*;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfWriter;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

@Service
@RequiredArgsConstructor
public class ReportService {

    private final PerformanceRepository performanceRepository;
    private final MachineFailureRepository machineFailureRepository;

    public byte[] generateDailyReport(LocalDate date) throws DocumentException {
        Document document = new Document(PageSize.A4);
        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        PdfWriter.getInstance(document, outputStream);

        document.open();

        // Add title
        Font titleFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 18);
        Paragraph title = new Paragraph("Daily Production Report - " + date.format(DateTimeFormatter.ISO_DATE), titleFont);
        title.setAlignment(Element.ALIGN_CENTER);
        title.setSpacingAfter(20);
        document.add(title);

        // Add performance section
        addPerformanceSection(document, date);
        
        // Add page break
        document.newPage();
        
        // Add machine interventions section
        addMachineInterventionsSection(document, date);

        document.close();
        return outputStream.toByteArray();
    }

    private void addPerformanceSection(Document document, LocalDate date) throws DocumentException {
        String dateStr = date.format(DateTimeFormatter.ISO_DATE);
        List<Performance> performances = performanceRepository.findByDate(dateStr);

        Font sectionFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 14);
        Paragraph sectionTitle = new Paragraph("Performance Logs", sectionFont);
        sectionTitle.setSpacingAfter(10);
        document.add(sectionTitle);

        if (performances.isEmpty()) {
            document.add(new Paragraph("No performance logs for this date."));
            return;
        }

        PdfPTable table = new PdfPTable(5);
        table.setWidthPercentage(100);
        table.setSpacingBefore(10);

        // Add table headers
        addTableHeader(table, "Order Reference", "Produced", "Production Target", "Defects", "Hour");

        // Add table rows
        for (Performance performance : performances) {
            table.addCell(performance.getOrderRef() != null ? performance.getOrderRef().toString() : "N/A");
            table.addCell(String.valueOf(performance.getProduced()));
            table.addCell(String.valueOf(performance.getProductionTarget()));
            table.addCell(String.valueOf(performance.getDefects()));
            table.addCell(performance.getHour());
        }

        document.add(table);
    }

    private void addMachineInterventionsSection(Document document, LocalDate date) throws DocumentException {
        String dateStr = date.format(DateTimeFormatter.ISO_DATE);
        List<MachineFailure> interventions = machineFailureRepository.findByDate(dateStr);

        Font sectionFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 14);
        Paragraph sectionTitle = new Paragraph("Machine Interventions", sectionFont);
        sectionTitle.setSpacingAfter(10);
        document.add(sectionTitle);

        if (interventions.isEmpty()) {
            document.add(new Paragraph("No machine interventions for this date."));
            return;
        }

        PdfPTable table = new PdfPTable(4);
        table.setWidthPercentage(100);
        table.setSpacingBefore(10);

        // Add table headers
        addTableHeader(table, "Machine Reference", "Time Spent", "Description", "Technician");

        // Add table rows
        for (MachineFailure intervention : interventions) {
            table.addCell(intervention.getMachineReference());
            table.addCell(String.valueOf(intervention.getTimeSpent()));
            table.addCell(intervention.getDescription());
            table.addCell(intervention.getTechnician_name());
        }

        document.add(table);
    }

    private void addTableHeader(PdfPTable table, String... headers) {
        Font headerFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD);
        for (String header : headers) {
            PdfPCell cell = new PdfPCell(new Phrase(header, headerFont));
            cell.setHorizontalAlignment(Element.ALIGN_CENTER);
            cell.setBackgroundColor(Color.LIGHT_GRAY);
            table.addCell(cell);
        }
    }
} 
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';

class SendNotificationView extends StatelessWidget {
  const SendNotificationView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, child) {
        // If user is a technician, show no permission message
        if (provider.isTechnician) {
          return Center(
            child: Text(
              'You do not have permission to send notifications',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Color(0xC5000000),
              ),
            ),
          );
        }

        // Only show notification form for managers and supervisors
        return SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alert Type:',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
              SizedBox(height: 8),
              _buildAlertTypeOptions(provider),
              SizedBox(height: 24),
              
              Text(
                'Send to:',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
              SizedBox(height: 8),
              _buildRecipientOptions(provider),
              SizedBox(height: 24),

              Text(
                'Workshop number:',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
              SizedBox(height: 8),
              _buildWorkshopOptions(provider),
              SizedBox(height: 24),

              Text(
                'Chaine number:',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
              SizedBox(height: 8),
              _buildChaineOptions(provider),
              SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => provider.sendNotification(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF6BBFB5),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Text(
                    'Send',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlertTypeOptions(NotificationProvider provider) {
    return Column(
      children: [
        _buildRadioOption<AlertType>(
          title: 'Emergency Alert',
          value: AlertType.emergencyAlert,
          groupValue: provider.selectedAlertType,
          onChanged: provider.setAlertType,
        ),
        _buildRadioOption<AlertType>(
          title: 'Efficiency Drop Alert',
          value: AlertType.efficiencyDropAlert,
          groupValue: provider.selectedAlertType,
          onChanged: provider.setAlertType,
        ),
        _buildRadioOption<AlertType>(
          title: 'Production Delay Alert',
          value: AlertType.productionDelayAlert,
          groupValue: provider.selectedAlertType,
          onChanged: provider.setAlertType,
        ),
        _buildRadioOption<AlertType>(
          title: 'Machine Failure',
          value: AlertType.machineFailure,
          groupValue: provider.selectedAlertType,
          onChanged: provider.setAlertType,
        ),
      ],
    );
  }

  Widget _buildRecipientOptions(NotificationProvider provider) {
    return Column(
      children: [
        _buildRadioOption<RecipientType>(
          title: 'Managers and supervisors',
          value: RecipientType.managersAndSupervisors,
          groupValue: provider.selectedRecipient,
          onChanged: provider.setRecipient,
          enabled: provider.canSelectRecipient(RecipientType.managersAndSupervisors),
        ),
        _buildRadioOption<RecipientType>(
          title: 'Technicians',
          value: RecipientType.technicians,
          groupValue: provider.selectedRecipient,
          onChanged: provider.setRecipient,
          enabled: provider.canSelectRecipient(RecipientType.technicians),
        ),
        _buildRadioOption<RecipientType>(
          title: 'Everyone',
          value: RecipientType.everyone,
          groupValue: provider.selectedRecipient,
          onChanged: provider.setRecipient,
          enabled: provider.canSelectRecipient(RecipientType.everyone),
        ),
      ],
    );
  }

  Widget _buildWorkshopOptions(NotificationProvider provider) {
    return Row(
      children: [1, 2, 3].map((number) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _buildNumberOption(
              number: number,
              isSelected: provider.selectedWorkshop == number,
              onTap: () => provider.setWorkshop(number),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChaineOptions(NotificationProvider provider) {
    return Row(
      children: [1, 2, 3].map((number) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _buildNumberOption(
              number: number,
              isSelected: provider.selectedChaine == number,
              onTap: () => provider.setChaine(number),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRadioOption<T>({
    required String title,
    required T value,
    required T? groupValue,
    required Function(T) onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Color(0xC5000000),
          ),
        ),
        leading: Radio<T>(
          value: value,
          groupValue: groupValue,
          onChanged: enabled ? (T? newValue) {
            if (newValue != null) onChanged(newValue);
          } : null,
          activeColor: Color(0xFF6BBFB5),
        ),
      ),
    );
  }

  Widget _buildNumberOption({
    required int number,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF6BBFB5) : Colors.transparent,
          border: Border.all(
            color: Color(0xFF6BBFB5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          number.toString(),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: isSelected ? Colors.white : Color(0xFF6BBFB5),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
} 
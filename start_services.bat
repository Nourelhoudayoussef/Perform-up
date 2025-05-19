@echo off
echo Starting services...

echo Starting Flask Chatbot...
start "chatbot" cmd /k "cd chatbot && python app.py"

echo Starting Spring Boot Backend...
start "pfeBack" cmd /k "cd pfeBack && mvn spring-boot:run"

echo Services started!
echo Flask Chatbot: http://localhost:5001
echo Spring Boot Backend: http://localhost:8080
echo.
echo Remember to log in again in your Flutter app to get a new JWT token.
echo.
echo Press any key to exit...
pause > nul 
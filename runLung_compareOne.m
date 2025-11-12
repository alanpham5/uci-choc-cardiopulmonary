clear; clc;

%% --- Plot and style settings (tweakable) ---
lineWidth = 2;              % Line thickness
axFontSize = 14;            % Axis label font size
tickFontSize = 12;          % Tick label font size
patientColor = [0 0 1];     % Blue for patient
healthyColor = [0.3 0.3 0.3]; % Dark grey for healthy
healthyAlpha = 0.6;         % Opacity for healthy line

%% File setup
patientIndex = 1;
patientfile = 'patient_lung_sim_results.csv';
healthyfile = 'healthy_patient_lung_sim_results.csv';
modelName = 'Modelo_Respiratorio';

%% Load parameter tables
P = readtable(patientfile, 'PreserveVariableNames', true);
H = readtable(healthyfile, 'PreserveVariableNames', true);

%% Extract patient-specific parameters
LC = P.LC(patientIndex);
TC = P.TC(patientIndex);
CR = P.CR(patientIndex);
PR = P.PR(patientIndex);
Cs = P.Cs(patientIndex);

patientName = sprintf('Patient%d', patientIndex);

%% Create folder for patient images
if ~exist(patientName, 'dir')
    mkdir(patientName);
end

%% Extract healthy reference parameters
LC_h = H.LC(1);
TC_h = H.TC(1);
CR_h = H.CR(1);
PR_h = H.PR(1);
Cs_h = H.Cs(1);

%% Ventilator settings
FR = 15;   % breaths/min
PEEP = 5;  % cmH2O
PP = 10;   % cmH2O
E = 2;     % inhale:exhale ratio
StopTime = '10';

%% --- Patient Simulation ---
assignin('base','CL', LC); assignin('base','Cw', TC);
assignin('base','Rc', CR); assignin('base','Rp', PR);
assignin('base','Cs', Cs);

assignin('base','f', LC); assignin('base','g', TC);
assignin('base','h', CR); assignin('base','j', PR);
assignin('base','k', Cs);

assignin('base','a', FR); assignin('base','b', PEEP);
assignin('base','c', PP); assignin('base','d', round(1/(1+1),2)*100);

load_system(modelName);
simOut_patient = sim(modelName, 'StopTime', StopTime);
Bio_patient = simOut_patient.get('BioData');
volumen_patient = simOut_patient.get('volumen');
t_patient = volumen_patient(:,1);
V_patient = volumen_patient(:,2);

%% --- Healthy Simulation ---
assignin('base','CL', LC_h); assignin('base','Cw', TC_h);
assignin('base','Rc', CR_h); assignin('base','Rp', PR_h);
assignin('base','Cs', Cs_h);

assignin('base','f', LC_h); assignin('base','g', TC_h);
assignin('base','h', CR_h); assignin('base','j', PR_h);
assignin('base','k', Cs_h);

assignin('base','FR', FR); assignin('base','PEEP', PEEP);
assignin('base','PP', PP); assignin('base','E', E);

simOut_healthy = sim(modelName, 'StopTime', StopTime);
Bio_healthy = simOut_healthy.get('BioData');
volumen_healthy = simOut_healthy.get('volumen');
t_healthy = volumen_healthy(:,1);
V_healthy = volumen_healthy(:,2);

%% --- Overlay all 6 signals (main figure) ---
figure('Name','Patient vs Healthy Simulation','NumberTitle','off');

subplot(3,2,1);
hPatient = plot(Bio_patient.time,Bio_patient.signals(1).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(1).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
title('Ventilator Pressure'); xlabel('Time (s)'); ylabel('Pressure (cmH2O)');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);

subplot(3,2,2);
hPatient = plot(Bio_patient.time,Bio_patient.signals(2).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(2).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
title('Alveolar Pressure'); xlabel('Time (s)'); ylabel('Pressure (cmH2O)');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);

subplot(3,2,3);
hPatient = plot(Bio_patient.time,Bio_patient.signals(3).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(3).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
title('Transpulmonary Pressure'); xlabel('Time (s)'); ylabel('Pressure (cmH2O)');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);

subplot(3,2,4);
hPatient = plot(Bio_patient.time,Bio_patient.signals(4).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(4).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
title('Respiratory Flow'); xlabel('Time (s)'); ylabel('Flow (L/s)');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);

subplot(3,2,5);
hPatient = plot(Bio_patient.time,Bio_patient.signals(5).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(5).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
title('Dead Space Flow'); xlabel('Time (s)'); ylabel('Flow (L/s)');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);

subplot(3,2,6);
hPatient = plot(t_patient,V_patient,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(t_healthy,V_healthy,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
title('Lung Volume'); xlabel('Time (s)'); ylabel('Volume (L)');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);

%% --- Separate detailed figures and save as PNGs ---
% Transpulmonary Pressure
fig1 = figure('Name','Transpulmonary Pressure','NumberTitle','off');
hPatient = plot(Bio_patient.time,Bio_patient.signals(3).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(3).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
xlabel('Time (s)'); ylabel('Pressure (cmH2O)'); title('Transpulmonary Pressure vs Time');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);
saveas(fig1, fullfile(patientName, sprintf('Transpulmonary_Pressure_%s.png', patientName)));

% Alveolar Flow
fig2 = figure('Name','Alveolar Flow','NumberTitle','off');
hPatient = plot(Bio_patient.time,Bio_patient.signals(6).values,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(Bio_healthy.time,Bio_healthy.signals(6).values,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
xlabel('Time (s)'); ylabel('Flow (L/s)'); title('Alveolar Flow vs Time');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);
saveas(fig2, fullfile(patientName, sprintf('Alveolar_Flow_%s.png', patientName)));

% Lung Volume
fig3 = figure('Name','Lung Volume','NumberTitle','off');
hPatient = plot(t_patient,V_patient,'Color',patientColor,'LineWidth',lineWidth); hold on;
hHealthy = plot(t_healthy,V_healthy,'Color',healthyColor,'LineWidth',lineWidth);
hHealthy.Color(4) = healthyAlpha;
xlabel('Time (s)'); ylabel('Volume (L)'); title('Lung Volume vs Time');
grid on; set(gca,'FontSize',tickFontSize); legend('Patient','Healthy','FontSize',axFontSize);
saveas(fig3, fullfile(patientName, sprintf('Lung_Volume_%s.png', patientName)));
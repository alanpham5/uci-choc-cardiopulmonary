%% runPatientSim_Simulink_FullPlots_Labeled.m
% Script to run patient-specific simulation using Simulink model
% Computes patient-specific parameters and saves all 6 plots from Ventiladorcito GUI

%% User parameters
infile = 'choc-data-all.csv';
patientIndex = 3;           

%% Load patient data
T = readtable(infile, 'PreserveVariableNames', true);

age = T.Age(patientIndex);
gender = string(T.Gender(patientIndex));
weight = T.("Wt (kg)")(patientIndex);
height = T.("Ht (cm)")(patientIndex);
HI = T.("Mean HI")(patientIndex);
FEV1 = T.FEV1(patientIndex);
FEF2575 = T.("FEF 25-75")(patientIndex);

%% Compute patient-specific parameters
HIref = 2.5;
% Sigmoid coefficients for each parameter
c_LC = 9.5;  w_LC = 3.0;
c_TC = 10.0; w_TC = 3.2;
c_CR = 10.5; w_CR = 2.8;
c_PR = 9.0;  w_PR = 3.5;

% Age-based thoracic compliance
if age>=6 && age<=10
    TCo=2;
elseif age>10 && age<=17
    TCo=1.75;
else
    TCo=1.25;
end

% Height-based lung compliance
LCo = (0.713 * height.^2.836 * 1e-4) / 1000;

% Baseline resistances
if gender=="Female"
    CRo=1.156; PRo=0.204;
else
    CRo=0.867; PRo=0.153;
end

% Total drop fractions
L_LC = 0.8;
L_TC = 0.8;
L_CR = 0.8;
L_PR = 0.8;

% Sigmoid response for each parameter
S_HI_LC  = 1/(1 + exp(-(HI - c_LC)/w_LC));
S_ref_LC = 1/(1 + exp(-(HIref - c_LC)/w_LC));
norm_LC  = (S_HI_LC - S_ref_LC) / (1 - S_ref_LC);

S_HI_TC  = 1/(1 + exp(-(HI - c_TC)/w_TC));
S_ref_TC = 1/(1 + exp(-(HIref - c_TC)/w_TC));
norm_TC  = (S_HI_TC - S_ref_TC) / (1 - S_ref_TC);

S_HI_CR  = 1/(1 + exp(-(HI - c_CR)/w_CR));
S_ref_CR = 1/(1 + exp(-(HIref - c_CR)/w_CR));
norm_CR  = (S_HI_CR - S_ref_CR) / (1 - S_ref_CR);

S_HI_PR  = 1/(1 + exp(-(HI - c_PR)/w_PR));
S_ref_PR = 1/(1 + exp(-(HIref - c_PR)/w_PR));
norm_PR  = (S_HI_PR - S_ref_PR) / (1 - S_ref_PR);

% Apply sigmoid-based decreases
if HI <= HIref
    LC = LCo;
    TC = TCo;
    CR = CRo;
    PR = PRo;
else
    LC = LCo * (1 - L_LC * norm_LC);
    TC = TCo * (1 - L_TC * norm_TC);
    CR = CRo * (1 - L_CR * norm_CR);
    PR = PRo * (1 - L_PR * norm_PR);
end

Cs = 0.005;

%% Assign parameters to base workspace for Simulink
% Mechanical parameters
assignin('base','CL', LC);
assignin('base','Cw', TC);
assignin('base','Rc', CR);
assignin('base','Rp', PR);
assignin('base','Cs', Cs);

% Also assign GUI-style variable names
assignin('base','f', LC);   % CL
assignin('base','g', TC);   % Cw
assignin('base','h', CR);   % Rc
assignin('base','j', PR);   % Rp
assignin('base','k', Cs);   % Cs

% Ventilator parameters
assignin('base','FR', 15);
assignin('base','PEEP', 0);
assignin('base','PP', 10);
assignin('base','E', 1);

% GUI-style equivalents
assignin('base','a', 15);   % FR
assignin('base','b', 0);    % PEEP
assignin('base','c', 10);   % PP
assignin('base','d', round(1/(1+1),2)*100); % E converted like GUI does (d = round(1/(E+1),2)*100)

%% Run Simulink simulation
modelName = 'Modelo_Respiratorio';
load_system(modelName);
simOut = sim(modelName, 'StopTime', '10');

%% Extract signals
BioData = simOut.get('BioData');
volumen = simOut.get('volumen');
time = BioData.time;

%% Plot signals
figure;
subplot(3,2,1);
plot(time,BioData.signals(1).values,'LineWidth',1.5); grid on;
title('Ventilator Pressure'); xlabel('Time (s)'); ylabel('Pressure (cmH2O)');
subplot(3,2,2);
plot(time,BioData.signals(2).values,'LineWidth',1.5); grid on;
title('Alveolar Pressure'); xlabel('Time (s)'); ylabel('Pressure (cmH2O)');
subplot(3,2,3);
plot(time,BioData.signals(3).values,'LineWidth',1.5); grid on;
title('Transpulmonary Pressure'); xlabel('Time (s)'); ylabel('Pressure (cmH2O)');
subplot(3,2,4);
plot(time,BioData.signals(4).values,'LineWidth',1.5); grid on;
title('Respiratory Flow'); xlabel('Time (s)'); ylabel('Flow (L/s)');
subplot(3,2,5);
plot(time,BioData.signals(5).values,'LineWidth',1.5); grid on;
title('Dead Space Flow'); xlabel('Time (s)'); ylabel('Flow (L/s)');
subplot(3,2,6);
plot(volumen(:,1),volumen(:,2),'LineWidth',1.5); grid on;
title('Alveolar Flow / Lung Volume'); xlabel('Time (s)'); ylabel('Flow (L/s) / Volume (L)');
saveas(gcf,sprintf('patient%d_allPlots_labeled.png', patientIndex));

%% Lung volume plot
figure;
plot(volumen(:,1), volumen(:,2), 'LineWidth', 1.5); grid on;
title('Lung Volume'); xlabel('Time (s)'); ylabel('Volume (L)');
saveas(gcf,sprintf('patient%d_lungVolume.png', patientIndex));

%% Display calculated parameters
disp(' ');
disp(['=== Patient ' num2str(patientIndex) ' Parameters ===']);
disp(['Age: ' num2str(age) ' years']);
disp(['Gender: ' char(gender)]);
disp(['Weight: ' num2str(weight,'%.1f') ' kg']);
disp(['Height: ' num2str(height,'%.1f') ' cm']);
disp(['HI: ' num2str(HI,'%.2f')]);

disp(' ');
disp('Derived Mechanical Parameters:');
disp(['Lung Compliance (CL): ' num2str(LC,'%.4f') ' L/cmH2O']);
disp(['Chest Wall Compliance (Cw): ' num2str(TC,'%.4f') ' L/cmH2O']);
disp(['Central Resistance (Rc): ' num2str(CR,'%.4f') ' cmH2O·s/L']);
disp(['Peripheral Resistance (Rp): ' num2str(PR,'%.4f') ' cmH2O·s/L']);
disp(['Series Compliance (Cs): ' num2str(Cs,'%.4f') ' L/cmH2O']);
disp('=============================');
disp(' ');
disp('All 6 plots and lung volume plot saved.');

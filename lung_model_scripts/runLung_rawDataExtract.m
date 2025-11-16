%% User parameters
infile = 'choc-data-all.csv';
outputFolder = 'patient_time_series_data'; % Folder to store all CSV files

%% Create output folder if it doesn't exist
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

%% Available metrics for saving
availableMetrics = {
    'ventilator_pressure', ...
    'alveolar_pressure', ...
    'transpulmonary_pressure', ...
    'respiratory_flow', ...
    'dead_space_flow', ...
    'alveolar_flow', ...
    'lung_volume' ...
};

%% Display available metrics
fprintf('Available metrics:\n');
for i = 1:length(availableMetrics)
    fprintf('%d. %s\n', i, availableMetrics{i});
end

%% User input for metric selection with validation
validInput = false;
while ~validInput
    userInput = input(sprintf('\nSelect metric to save (1-%d): ', length(availableMetrics)), 's');
    
    if isempty(userInput)
        fprintf('Please enter a number.\n');
        continue;
    end
    
    metricIndex = str2double(userInput);
    
    if isnan(metricIndex) || ~isreal(metricIndex) || metricIndex < 1 || metricIndex > length(availableMetrics)
        fprintf('Invalid input. Please enter a number between 1 and %d.\n', length(availableMetrics));
    else
        validInput = true;
    end
end

selectedMetric = availableMetrics{metricIndex};
fprintf('Selected metric: %s\n', selectedMetric);

%% Load patient data
T = readtable(infile, 'PreserveVariableNames', true);
numPatients = size(T, 1);

%% Constants
HIref = 2.5;         
Cs = 0.005;         

% Sigmoid coefficients for parameter scaling
c_FVC = 1.00; w_FVC = 0.10;  % Lung compliance (% predicted)
c_TC  = 10.0; w_TC  = 3.2;   % Thoracic compliance
c_CR  = 1.00; w_CR  = 0.10;  % Central resistance (% predicted)
c_PR  = 1.00; w_PR  = 0.10;  % Peripheral resistance (% predicted)

% Maximum fractional adjustments
L_LC = 0.20;     % Max fractional drop for LC
L_TC = 0.8;      % Max fractional drop for TC
L_CR = 0.20;     % Max 20% increase for CR
L_PR = 0.40;     % Max 40% increase for PR

% Additional shape parameter for LC
gamma_LC = 1.5; % Steepness control for LC

% Baseline resistances (fixed)
CRo = 2.0;      % Central airway resistance
PRo = 0.5;      % Peripheral airway resistance

% Ventilator settings
FR = 15;  % Breathing frequency
PEEP = 5; % Positive End-Expiratory Pressure
PP = 10;  % Peak Pressure
E = 2;    % Inhale:Exhale ratio

%% Initialize results table for time series data
timeSeriesResults = table();

%% Iterate through all patients
for patientIndex = 1:numPatients
    fprintf('Processing patient %d/%d for %s...\n', patientIndex, numPatients, selectedMetric);
    
    try
        %% Extract patient data
        age = T.Age(patientIndex);
        gender = string(T.Gender(patientIndex));
        weight = T.("Wt (kg)")(patientIndex);
        height_cm = T.("Ht (cm)")(patientIndex);  % Renamed to avoid conflict
        HI = T.("Mean HI")(patientIndex);
        FEV1 = T.FEV1(patientIndex);
        FEF2575 = T.("FEF 25-75")(patientIndex);
        FVCpct = T.("FVC% predicted")(patientIndex);
        PEFpct = T.("PEF %predicted")(patientIndex);
        FEF2575pct_post = T.("FEF25-75 post %predicted")(patientIndex);
        VO2max = T.("VO2 max (mL/kg/min)")(patientIndex);  

        %% Compute patient-specific parameters
        % Age-based thoracic compliance
        if age >= 6 && age <= 10
            TCo = 2;
        elseif age > 10 && age <= 17
            TCo = 1.75;
        else
            TCo = 1.25;
        end

        % Height-based baseline lung compliance
        LCo = (0.713 * height_cm.^2.836 * 1e-4) / 1000;

        % --- Lung Compliance (FVC % predicted, decreasing relation) ---
        S_FVC = 1 / (1 + exp(-(FVCpct - c_FVC)/w_FVC));
        S_ref_FVC = 1 / (1 + exp(-(1.0 - c_FVC)/w_FVC)); % reference at 100%
        norm_FVC = max(0, (S_ref_FVC - S_FVC) / S_ref_FVC);
        LC = LCo * (1 - L_LC * (norm_FVC ^ gamma_LC));  % decreases with FVCpct

        % --- Thoracic Compliance (HI-based) ---
        S_HI_TC  = 1 / (1 + exp(-(HI - c_TC)/w_TC));
        S_ref_TC = 1 / (1 + exp(-(HIref - c_TC)/w_TC));
        norm_TC  = max(0, (S_HI_TC - S_ref_TC) / (1 - S_ref_TC));
        TC = TCo * (1 - L_TC * norm_TC);

        % --- Central Airway Resistance (PEF % predicted, flipped) ---
        S_PEF = 1 / (1 + exp(-(PEFpct - c_CR)/w_CR));
        S_ref_PEF = 1 / (1 + exp(-(1.0 - c_CR)/w_CR));  % reference 100%
        norm_PEF = max(0, 1 - (S_PEF / S_ref_PEF));
        CR = CRo * (1 + L_CR * norm_PEF);

        % --- Peripheral Airway Resistance (FEF25-75 % predicted, flipped) ---
        S_FEF = 1 / (1 + exp(-(FEF2575pct_post - c_PR)/w_PR));
        S_ref_FEF = 1 / (1 + exp(-(1.0 - c_PR)/w_PR));
        norm_FEF = max(0, 1 - (S_FEF / S_ref_FEF));
        PR = PRo * (1 + L_PR * norm_FEF);

        %% Assign parameters to base workspace for Simulink
        assignin('base','CL', LC);
        assignin('base','Cw', TC);
        assignin('base','Rc', CR);
        assignin('base','Rp', PR);
        assignin('base','Cs', Cs);

        % GUI-style variable names
        assignin('base','f', LC);
        assignin('base','g', TC);
        assignin('base','h', CR);
        assignin('base','j', PR);
        assignin('base','k', Cs);

        % Ventilator parameters
        assignin('base','FR', FR);
        assignin('base','PEEP', PEEP);
        assignin('base','PP', PP);
        assignin('base','E', E);

        %% Run Simulink simulation
        modelName = 'Modelo_Respiratorio';
        load_system(modelName);
        simOut = sim(modelName, 'StopTime', '10');

        %% Extract signals - USE ALL TIME POINTS (0-10 seconds)
        BioData = simOut.get('BioData');
        volumen = simOut.get('volumen');
        time = BioData.time;

        % Use ALL time points from 0-10 seconds (no steady-state filtering)
        % Extract all signals for complete time series
        ventilator_pressure = BioData.signals(1).values;
        alveolar_pressure = BioData.signals(2).values;
        transpulmonary_pressure = BioData.signals(3).values;
        respiratory_flow = BioData.signals(4).values;
        dead_space_flow = BioData.signals(5).values;
        alveolar_flow = BioData.signals(6).values;
        lung_volume = volumen(:,2);
        time_all = time;

        %% Select the requested metric
        switch selectedMetric
            case 'ventilator_pressure'
                metric_data = ventilator_pressure;
            case 'alveolar_pressure'
                metric_data = alveolar_pressure;
            case 'transpulmonary_pressure'
                metric_data = transpulmonary_pressure;
            case 'respiratory_flow'
                metric_data = respiratory_flow;
            case 'dead_space_flow'
                metric_data = dead_space_flow;
            case 'alveolar_flow'
                metric_data = alveolar_flow;
            case 'lung_volume'
                metric_data = lung_volume;
        end

        %% Create table for this patient's time series data
        patientTimeData = table();
        patientTimeData.time = time_all;
        patientTimeData.(selectedMetric) = metric_data;
        patientTimeData.patientIndex = repmat(patientIndex, size(time_all, 1), 1);
        patientTimeData.age = repmat(age, size(time_all, 1), 1);
        patientTimeData.gender = repmat(gender, size(time_all, 1), 1);
        patientTimeData.HI = repmat(HI, size(time_all, 1), 1);
        patientTimeData.FVCpct = repmat(FVCpct, size(time_all, 1), 1);

        %% Append to main results table
        timeSeriesResults = [timeSeriesResults; patientTimeData];

        fprintf('  Patient %d completed successfully.\n', patientIndex);
        fprintf('  Time points saved: %d (0-10 seconds)\n', size(time_all, 1));

    catch ME
        fprintf('  ERROR processing patient %d: %s\n', patientIndex, ME.message);
        
        % Create empty row with NaN for failed patients (0-10 seconds)
        emptyTime = (0:0.01:10)'; % From 0 to 10 seconds
        numEmptyPoints = size(emptyTime, 1);
        
        patientTimeData = table();
        patientTimeData.time = emptyTime;
        patientTimeData.(selectedMetric) = nan(numEmptyPoints, 1);
        patientTimeData.patientIndex = repmat(patientIndex, numEmptyPoints, 1);
        patientTimeData.age = repmat(age, numEmptyPoints, 1);
        patientTimeData.gender = repmat(gender, numEmptyPoints, 1);
        patientTimeData.HI = repmat(HI, numEmptyPoints, 1);
        patientTimeData.FVCpct = repmat(FVCpct, numEmptyPoints, 1);

        timeSeriesResults = [timeSeriesResults; patientTimeData];
    end
end

%% Save time series data to CSV
outputFilename = fullfile(outputFolder, sprintf('all_patients_%s_timeseries.csv', selectedMetric));
writetable(timeSeriesResults, outputFilename);

%% Also save individual patient files (optional)
% fprintf('\nSaving individual patient files...\n');
% for patientIndex = 1:numPatients
%     patientData = timeSeriesResults(timeSeriesResults.patientIndex == patientIndex, :);
%     if ~isempty(patientData)
%         individualFilename = fullfile(outputFolder, sprintf('patient_%02d_%s.csv', patientIndex, selectedMetric));
%         writetable(patientData, individualFilename);
%     end
% end

%% Display summary
fprintf('\nPatient processing complete!\n');
fprintf('Time series data saved to: %s\n', outputFilename);
fprintf('Individual patient files saved to: %s/\n', outputFolder);
fprintf('Metric: %s\n', selectedMetric);
fprintf('Total time points: %d\n', size(timeSeriesResults, 1));
fprintf('Time range: %.2f to %.2f seconds\n', min(timeSeriesResults.time), max(timeSeriesResults.time));
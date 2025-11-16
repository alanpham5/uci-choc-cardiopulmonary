clearvars; close all; rng('shuffle');

%% User parameters
numPatients = 62;
outputFolder = 'healthy_patient_time_series_data';
outputFilename = 'healthy_patient_summary_results.csv';

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

%% Constants / Reference values
HIref = 2.5;
Cs = 0.005;
FR = 15; PEEP = 5; PP = 10; E = 2;

% Default mechanical parameters (fixed)
LC_ref = 0.2;   % Reference Lung compliance (L/cmH2O)
TC_ref = 0.2;   % Thoracic compliance (L/cmH2O)
CR_ref = 2.0;   % Central airway resistance (cmH2O·s/L)
PR_ref = 0.5;   % Peripheral airway resistance (cmH2O·s/L)

%% Generate demographic data
Age = randi([13,21], numPatients, 1);
Gender = strings(numPatients,1);
Ht_cm = zeros(numPatients,1);
Wt_kg = zeros(numPatients,1);
FEV1 = zeros(numPatients,1);
FEF2575 = zeros(numPatients,1);

for i = 1:numPatients
    if rand() < 0.5
        Gender(i) = "Male";
        adult_mean_h = 175; adult_sd_h = 7; min_h = 150; max_h = 200;
    else
        Gender(i) = "Female";
        adult_mean_h = 162; adult_sd_h = 7; min_h = 145; max_h = 185;
    end

    frac = 0.75 + 0.20 * ((Age(i)-13)/8);
    Ht_mean = frac * adult_mean_h;
    Ht_candidate = round(Ht_mean + adult_sd_h * randn(), 1);
    while Ht_candidate < min_h || Ht_candidate > max_h
        Ht_candidate = round(Ht_mean + adult_sd_h * randn(), 1);
    end
    Ht_cm(i) = Ht_candidate;

    BMI = 18.5 + (25-18.5)*rand();
    H_m = Ht_cm(i)/100;
    Wt_kg(i) = round(BMI * H_m^2, 1);

    meanFEV1 = 0.025*Ht_cm(i) - 1.0;
    FEV1(i) = round(max(0.5, meanFEV1 + 0.3*randn()), 2);
    FEF2575(i) = round(1.5 + 1.5*rand(), 2);
end

%% Initialize results tables
summaryResults = table();
timeSeriesResults = table();

%% Load Simulink model
modelName = 'Modelo_Respiratorio';
load_system(modelName);

%% Iterate through patients
for patientIndex = 1:numPatients
    fprintf('Processing healthy patient %d/%d for %s...\n', patientIndex, numPatients, selectedMetric);

    age = Age(patientIndex);
    gender = Gender(patientIndex);
    weight = Wt_kg(patientIndex);
    height = Ht_cm(patientIndex);
    HI = HIref;
    FEV1v = FEV1(patientIndex);
    FEF2575v = FEF2575(patientIndex);

    % Mechanical parameters with variability
    variability = 0.15; % percentage variation
    LC = LC_ref * (1 + variability*randn()); 
    TC = TC_ref * (1 + variability*randn());
    CR = CR_ref * (1 + variability*randn());
    PR = PR_ref * (1 + variability*randn());

    % Clamp values within physiological limits
    LC = max(min(LC, 0.3), 0.05);  
    TC = max(min(TC, 1.0), 0.05);
    CR = max(min(CR, 5.0), 0.5);
    PR = max(min(PR, 1.0), 0.05);

    % Assign to Simulink (GUI-style included)
    assignin('base','CL', LC); assignin('base','Cw', TC);
    assignin('base','Rc', CR); assignin('base','Rp', PR);
    assignin('base','Cs', Cs);
    assignin('base','f', LC); assignin('base','g', TC);
    assignin('base','h', CR); assignin('base','j', PR); assignin('base','k', Cs);
    assignin('base','FR', FR); assignin('base','PEEP', PEEP);
    assignin('base','PP', PP); assignin('base','E', E);
    assignin('base','a', FR); assignin('base','b', PEEP);
    assignin('base','c', PP); assignin('base','d', round(1/(1+1),2)*100);

    % Run Simulink simulation
    try
        simOut = sim(modelName, 'StopTime', '10');

        BioData = simOut.get('BioData');
        volumen = simOut.get('volumen');
        time = BioData.time;

        % Use ALL time points (0-10 seconds) - no steady-state filtering
        % Extract ALL signals for time series data
        ventilator_pressure = BioData.signals(1).values;
        alveolar_pressure = BioData.signals(2).values;
        transpulmonary_pressure = BioData.signals(3).values;
        respiratory_flow = BioData.signals(4).values;
        dead_space_flow = BioData.signals(5).values;
        alveolar_flow = BioData.signals(6).values;
        lung_volume = volumen(:,2);
        time_all = time;

        %% Select the requested metric for time series saving
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

        %% Create time series table for this patient
        patientTimeData = table();
        patientTimeData.time = time_all;
        patientTimeData.(selectedMetric) = metric_data;
        patientTimeData.patientIndex = repmat(patientIndex, size(time_all, 1), 1);
        patientTimeData.age = repmat(age, size(time_all, 1), 1);
        patientTimeData.gender = repmat(gender, size(time_all, 1), 1);
        patientTimeData.height = repmat(height, size(time_all, 1), 1);
        patientTimeData.weight = repmat(weight, size(time_all, 1), 1);
        patientTimeData.HI = repmat(HI, size(time_all, 1), 1);
        patientTimeData.FEV1 = repmat(FEV1v, size(time_all, 1), 1);
        patientTimeData.FEF2575 = repmat(FEF2575v, size(time_all, 1), 1);
        
        % Mechanical parameters
        patientTimeData.LC = repmat(LC, size(time_all, 1), 1);
        patientTimeData.TC = repmat(TC, size(time_all, 1), 1);
        patientTimeData.CR = repmat(CR, size(time_all, 1), 1);
        patientTimeData.PR = repmat(PR, size(time_all, 1), 1);
        patientTimeData.Cs = repmat(Cs, size(time_all, 1), 1);

        %% Append to main time series table
        timeSeriesResults = [timeSeriesResults; patientTimeData];

        %% Also store summary metrics (using steady-state for summary stats)
        ss_idx = time_all >= 2;  % Still use steady-state for summary statistics
        lung_ss = lung_volume(ss_idx);
        transp_ss = transpulmonary_pressure(ss_idx);
        alv_ss = alveolar_pressure(ss_idx);
        flow_ss = respiratory_flow(ss_idx);
        dead_ss = dead_space_flow(ss_idx);
        alvFlow_ss = alveolar_flow(ss_idx);

        patientResult = table();
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1v;
        patientResult.FEF2575 = FEF2575v;

        patientResult.LC = round(LC,4);
        patientResult.TC = round(TC,4);
        patientResult.CR = round(CR,4);
        patientResult.PR = round(PR,4);
        patientResult.Cs = round(Cs,4);

        patientResult.Sim_LungVol_Mean = round(mean(lung_ss),4);
        patientResult.Sim_LungVol_Max = round(max(lung_ss),4);
        patientResult.Sim_LungVol_Std = round(std(lung_ss),4);
        patientResult.Sim_TransP_Mean = round(mean(transp_ss),4);
        patientResult.Sim_TransP_Max = round(max(transp_ss),4);
        patientResult.Sim_TransP_Std = round(std(transp_ss),4);
        patientResult.Sim_AlvP_PeakMax = round(max(alv_ss),4);
        patientResult.Sim_AlvP_PeakMin = round(min(alv_ss),4);
        patientResult.Sim_Flow_PeakMax = round(max(flow_ss),4);
        patientResult.Sim_Flow_Std = round(std(flow_ss),4);
        patientResult.Sim_DeadFlow_PeakMax = round(max(dead_ss),4);
        patientResult.Sim_DeadFlow_Std = round(std(dead_ss),4);
        patientResult.Sim_AlvFlow_Max = round(max(alvFlow_ss),4);
        patientResult.Sim_AlvFlow_Mean = round(mean(alvFlow_ss),4);
        patientResult.Sim_AlvFlow_Std = round(std(alvFlow_ss),4);

        summaryResults = [summaryResults; patientResult];

        fprintf('  Patient %d completed successfully.\n', patientIndex);
        fprintf('  Time points saved: %d (0-10 seconds)\n', size(time_all, 1));

    catch ME
        fprintf('  ERROR simulating patient %d: %s\n', patientIndex, ME.message);
        
        % Create empty time series data with NaN for failed patients (0-10 seconds)
        emptyTime = (0:0.01:10)'; % From 0 to 10 seconds
        numEmptyPoints = size(emptyTime, 1);
        
        patientTimeData = table();
        patientTimeData.time = emptyTime;
        patientTimeData.(selectedMetric) = nan(numEmptyPoints, 1);
        patientTimeData.patientIndex = repmat(patientIndex, numEmptyPoints, 1);
        patientTimeData.age = repmat(age, numEmptyPoints, 1);
        patientTimeData.gender = repmat(gender, numEmptyPoints, 1);
        patientTimeData.height = repmat(height, numEmptyPoints, 1);
        patientTimeData.weight = repmat(weight, numEmptyPoints, 1);
        patientTimeData.HI = repmat(HI, numEmptyPoints, 1);
        patientTimeData.FEV1 = repmat(FEV1v, numEmptyPoints, 1);
        patientTimeData.FEF2575 = repmat(FEF2575v, numEmptyPoints, 1);
        patientTimeData.LC = nan(numEmptyPoints, 1);
        patientTimeData.TC = nan(numEmptyPoints, 1);
        patientTimeData.CR = nan(numEmptyPoints, 1);
        patientTimeData.PR = nan(numEmptyPoints, 1);
        patientTimeData.Cs = repmat(Cs, numEmptyPoints, 1);

        timeSeriesResults = [timeSeriesResults; patientTimeData];

        % Also create summary entry with NaN
        patientResult = table();
        patientResult.patientIndex = patientIndex;
        patientResult.age = age;
        patientResult.gender = gender;
        patientResult.weight = weight;
        patientResult.height = height;
        patientResult.HI = HI;
        patientResult.FEV1 = FEV1v;
        patientResult.FEF2575 = FEF2575v;
        patientResult.LC = NaN; patientResult.TC = NaN;
        patientResult.CR = NaN; patientResult.PR = NaN;
        patientResult.Cs = round(Cs,4);
        patientResult.Sim_LungVol_Mean = NaN; patientResult.Sim_LungVol_Max = NaN; patientResult.Sim_LungVol_Std = NaN;
        patientResult.Sim_TransP_Mean = NaN; patientResult.Sim_TransP_Max = NaN; patientResult.Sim_TransP_Std = NaN;
        patientResult.Sim_AlvP_PeakMax = NaN; patientResult.Sim_AlvP_PeakMin = NaN;
        patientResult.Sim_Flow_PeakMax = NaN; patientResult.Sim_Flow_Std = NaN;
        patientResult.Sim_DeadFlow_PeakMax = NaN; patientResult.Sim_DeadFlow_Std = NaN;
        patientResult.Sim_AlvFlow_Max = NaN; patientResult.Sim_AlvFlow_Mean = NaN; patientResult.Sim_AlvFlow_Std = NaN;

        summaryResults = [summaryResults; patientResult];
    end
end

%% Save time series data to CSV
timeSeriesOutputFilename = fullfile(outputFolder, sprintf('healthy_patients_%s_timeseries.csv', selectedMetric));
writetable(timeSeriesResults, timeSeriesOutputFilename);

%% Save summary results to CSV
writetable(summaryResults, outputFilename);

% %% Also save individual patient files (optional)
% fprintf('\nSaving individual patient files...\n');
% for patientIndex = 1:numPatients
%     patientData = timeSeriesResults(timeSeriesResults.patientIndex == patientIndex, :);
%     if ~isempty(patientData)
%         individualFilename = fullfile(outputFolder, sprintf('healthy_patient_%02d_%s.csv', patientIndex, selectedMetric));
%         writetable(patientData, individualFilename);
%     end
% end

%% Display summary
fprintf('\nHealthy patient processing complete!\n');
fprintf('Time series data saved to: %s\n', timeSeriesOutputFilename);
fprintf('Summary results saved to: %s\n', outputFilename);
fprintf('Individual patient files saved to: %s/\n', outputFolder);
fprintf('Metric: %s\n', selectedMetric);
fprintf('Total time points: %d\n', size(timeSeriesResults, 1));
fprintf('Time range: %.2f to %.2f seconds\n', min(timeSeriesResults.time), max(timeSeriesResults.time));
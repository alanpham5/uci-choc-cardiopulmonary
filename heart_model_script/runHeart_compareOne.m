%% runHeart_compareOne.m
% Healthy (defaults) vs Patient (Pt Key = 1) on the Simscape Heart model
 
%% --- Robust project open (no cd required) ---
clear; clc;

scriptDir = fileparts(mfilename('fullpath'));        % .../Scripts/Work
projRoot  = fileparts(fileparts(scriptDir));         % project root
projPath  = fullfile(projRoot, 'HeartModel.prj');
assert(isfile(projPath), "HeartModel.prj not found at %s", projPath);
proj = openProject(projPath);

% Model path
mdlName = 'CardioVascularSystem';
mdlPath = fullfile(proj.RootFolder,'Models',[mdlName '.slx']);
load_system(mdlPath);

%% --- Find the CSV no matter where you dropped it ---
cands = { ...
    fullfile(proj.RootFolder,'choc-data-all_clean.csv'), ...
    fullfile(proj.RootFolder,'choc-data-all.csv'), ...
    fullfile(proj.RootFolder,'Scripts','Work','choc-data-all.csv'), ...
    fullfile(proj.RootFolder,'Scripts','Work','choc-data-all_clean.csv')};
infile = '';
for c = 1:numel(cands)
    if isfile(cands{c}), infile = cands{c}; break; end
end
assert(~isempty(infile), 'Could not find choc-data-all*.csv in project or Scripts/Work.');

%% --- Read with the *second* line as header (preserve original names) ---
opts = detectImportOptions(infile, 'Delimiter', ',');
opts.VariableNamesLine   = 2;        % real headers on line 2
opts.DataLines           = [3 Inf];  % data start on line 3
opts.VariableNamingRule  = 'preserve';
T = readtable(infile, opts);

%% --- Select patient by Pt Key (safer than raw row index) ---
ptKeyValue = 1;  % <— change if needed
vars = string(T.Properties.VariableNames);
m = (vars=="Pt Key") | (vars=="Pt Key ") | contains(vars,"Pt Key","IgnoreCase",true);
assert(any(m),'Could not find a "Pt Key" column');
ptKeyCol = char(vars(find(m,1)));

ix = find(T.(ptKeyCol)==ptKeyValue, 1);
assert(~isempty(ix), 'No row found for Pt Key = %d', ptKeyValue);

%% --- Pull inputs using flexible column matching ---
BSA     = getvFlex(T, {'BSA (m2)','BSA'},                   ix, 1.70);
HR_pat  = getvFlex(T, {'HR','HR max','HR max %','HR max.1'},ix, 75);

LVEDVi  = getvFlex(T, {'LVEDVi'},                           ix, NaN);
LVESVi  = getvFlex(T, {'LVESVi'},                           ix, NaN);
RVEDVi  = getvFlex(T, {'RVEDVi'},                           ix, NaN);

SBP     = getvFlex(T, {'SBP','Systolic BP','Systolic'},     ix, NaN);
DBP     = getvFlex(T, {'DBP','Diastolic BP','Diastolic'},   ix, NaN);

HI      = getvFlex(T, {'Mean HI','HI mean','Haller Index'}, ix, 2.5);
IVCraw  = getvFlex(T, {'IVC compression?'},                 ix, 0);
RVraw   = getvFlex(T, {'RV compression?'},                  ix, 0);
IVCcomp = asFlag(IVCraw);
RVcomp  = asFlag(RVraw);

%% ---------- RUN 1: HEALTHY (defaults) ----------
% Load pristine defaults
run(fullfile(proj.RootFolder,'Scripts','Initialization.m'));

% Use patient HR so time bases align, but otherwise keep defaults = "Healthy"
assignin('base','HeartRate', HR_pat);
tc_healthy = 60/HR_pat; 
ts = 0.16 + 0.3*tc_healthy;        % same timing relation you used before
assignin('base','tc', tc_healthy); 
assignin('base','ts', ts);

% Simulate ~2 beats
set_param(mdlName,'SignalLogging','on','StopTime',num2str(2*tc_healthy));
outHealthy = sim(mdlName);

% Grab signals
lvVolH  = tryGetVals(outHealthy,'VolumeInt_Left');   % LV volume (mL)
lvofH   = tryGetVals(outHealthy,'LVOF');             % Aortic outflow (mL/s)

%% ---------- RUN 2: PATIENT (mapped) ----------
% Reload defaults, then apply mapping
run(fullfile(proj.RootFolder,'Scripts','Initialization.m'));

% Map initial volumes from indexed values (if present)
if ~isnan(LVEDVi) && ~isnan(LVESVi) && ~isnan(BSA)
    LVEDV = LVEDVi * BSA; 
    LVESV = LVESVi * BSA;          % mL
    assignin('base','X120', LVEDV);% initial LV volume
end
if ~isnan(RVEDVi) && ~isnan(BSA)
    RVEDV = RVEDVi * BSA;          % mL
    assignin('base','X60', RVEDV); % initial RV volume
end

% Heart rate & timing
assignin('base','HeartRate', HR_pat);
tc_patient = 60/HR_pat; 
ts = 0.16 + 0.3*tc_patient;
assignin('base','tc', tc_patient); 
assignin('base','ts', ts);

% Optional arterial compliance scaling via SV/PP if BP + LV volumes exist
if exist('LVEDV','var') && exist('LVESV','var') && ~isnan(SBP) && ~isnan(DBP)
    PP   = max(5, SBP - DBP);            % mmHg
    SVlv = max(1, LVEDV - LVESV);        % mL
    Cart = SVlv / PP;                    % ~mmHg^-1·cm^3
    C1 = evalin('base','C1'); 
    C2 = evalin('base','C2');
    ratio = C1/(C1+C2+eps);
    assignin('base','C1', ratio*Cart);
    assignin('base','C2', (1-ratio)*Cart);
end

% HI-based venous/pulmonary compliance scaling (stronger on C3–C5)
mult = max(0.5, 1 - 0.06*(HI - 2.5));
C3 = evalin('base','C3'); C4 = evalin('base','C4'); 
C5 = evalin('base','C5'); C6 = evalin('base','C6');
assignin('base','C3', C3*(0.85*mult + 0.15));
assignin('base','C4', C4*mult);
assignin('base','C5', C5*mult);
assignin('base','C6', C6*(0.9*mult + 0.1));

% Compression flags tweak venous/pulmonary loop (non-valvular)
if IVCcomp
    assignin('base','R3', 1.2 * evalin('base','R3'));
    assignin('base','C3', 0.9 * evalin('base','C3'));
end
if RVcomp
    assignin('base','R6', 1.2 * evalin('base','R6'));
    assignin('base','C5', 0.9 * evalin('base','C5'));
end

% Simulate ~2 beats (now tc_patient exists)
set_param(mdlName,'SignalLogging','on','StopTime',num2str(2*tc_patient));
outPatient = sim(mdlName);

% Grab signals
lvVolP = tryGetVals(outPatient,'VolumeInt_Left');
lvofP  = tryGetVals(outPatient,'LVOF');%% ---------- PLOT EVERYTHING (HEALTHY vs PATIENT) ----------
% Flatten logsout -> map of name -> timeseries (safe against recursion)
mapH = flattenLogs_safe(outHealthy.logsout);
mapP = flattenLogs_safe(outPatient.logsout);

% Optional: limit to curated groups; set to false to plot all common signals
onlyGroups = true;
press = {'Aortic Pressure','Left Ventricular Pressure','Right Venous Atrial Pressure','Pulmonary Pressure','PiLa(t)','Pv'};
flows = {'LVOF','LVIF','RVOF','RVIF','LeftVentricleFlow'};
voles = {'VolumeInt','VolumeInt_Left','EL(t)'};
curated = [press, flows, voles];

% Convert keys to string arrays for robust set ops
kH = string(keys(mapH));
kP = string(keys(mapP));

if onlyGroups
    curatedStr = string(curated);
    namesCommon = curatedStr(ismember(curatedStr, intersect(kH, kP)));
else
    namesCommon = intersect(kH, kP);
end

namesCommon = sort(namesCommon);  % stable order

for i = 1:numel(namesCommon)
    nm = namesCommon(i);
    try
        tsH = mapH(char(nm));
        tsP = mapP(char(nm));

        figure('Name', char(nm), 'NumberTitle', 'off');
        plot(tsP.Time, tsP.Data, 'c', 'LineWidth', 1.8); hold on; grid on;
        plot(tsH.Time, tsH.Data, 'y', 'LineWidth', 1.8);
        title(char(nm), 'Interpreter','none');
        xlabel('Time (s)');
        ylabel( inferYLabel(char(nm)) );
        legend('Patient','Healthy','Location','best');
    catch ME
        warning('Skipping "%s": %s', char(nm), ME.message);
    end
end

function v = getvFlex(T, patterns, idx, def)
% Get value from the first column whose name equals OR contains any pattern.
% - Safely handles missing columns/values
% - Coerces numeric-looking strings to numbers
% - Leaves non-numeric strings (e.g., 'Y'/'N') as-is for asFlag()
    v = def;
    vars = string(T.Properties.VariableNames);
    for p = 1:numel(patterns)
        pat = string(patterns{p});
        j = find(vars == pat, 1);
        if isempty(j)
            j = find(contains(vars, pat, 'IgnoreCase', true), 1);
        end
        if ~isempty(j)
            col = T.(vars(j));
            if idx <= height(T)
                val = col(idx);
                % unwrap cellstr
                if iscell(val), val = val{1}; end
                % try numeric conversion; keep strings like 'Y'/'N'
                if ~isnumeric(val)
                    num = str2double(string(val));
                    if ~isnan(num)
                        v = num; 
                        return;
                    else
                        % keep original (text flag), let asFlag handle it
                        v = val; 
                        return;
                    end
                else
                    if ~(isnan(val) || isempty(val))
                        v = val; 
                        return;
                    end
                end
            end
        end
    end
    % if nothing found or usable, returns def
end

function tf = asFlag(x)
% Robust boolean parser: supports logical, numeric, and common text flags.
% True: 1, nonzero numbers, "Y","YES","TRUE","T","1"
% False: 0, "N","NO","FALSE","F","0","/","", "NA","N/A"
    if islogical(x)
        tf = x; 
        return;
    end
    if isnumeric(x)
        tf = x ~= 0;
        return;
    end
    s = upper(strtrim(string(x)));
    if isscalar(s)
        % common falsy tokens
        if ismember(s, ["N","NO","FALSE","F","0","/","","NA","N/A","NONE"])
            tf = false; 
            return;
        end
        % common truthy tokens
        if ismember(s, ["Y","YES","TRUE","T","1"])
            tf = true; 
            return;
        end
        % try numeric text
        num = str2double(s);
        if ~isnan(num)
            tf = num ~= 0; 
            return;
        end
    end
    % default fallback
    tf = false;
end


%% ===== Helpers you can paste at the end of the file =====

function ts = tryGetVals(out, name)
% Get a logged signal by name from logsout, or throw a helpful error.
    names = out.logsout.getElementNames;
    if any(strcmp(name, names))
        ts = out.logsout.getElement(name).Values;
    else
        error('Signal "%s" not found in logsout. Available: %s', ...
              name, strjoin(names, ', '));
    end
end

function m = flattenLogs_safe(logsout)
% Flatten nested Dataset/Signal structure into map: "path/name" -> timeseries
    m = containers.Map('KeyType','char','ValueType','any');
    visited = containers.Map('KeyType','char','ValueType','logical');
    allNames = logsout.getElementNames;
    for k = 1:numel(allNames)
        elem = logsout.getElement(allNames{k});
        addElem_safe(m, elem, elem.Name, 0, visited);
    end
end

function addElem_safe(m, elem, prefix, depth, visited)
% Safe recursive descent with cycle guard and duplicate-key protection
    if depth > 6, return; end  % hard depth guard

    cls  = class(elem);
    sigID = sprintf('%s|%s', cls, prefix);

    if isa(elem, 'Simulink.SimulationData.Signal')
        ts = elem.Values;
        if ~isempty(ts) && ~isempty(ts.Time)
            key = prefix;
            ctr = 1;
            while isKey(m, key)
                ctr = ctr + 1;
                key = sprintf('%s#%d', prefix, ctr);
            end
            m(key) = ts;
        end

    elseif isa(elem, 'Simulink.SimulationData.Dataset')
        if isKey(visited, sigID), return; end
        visited(sigID) = true;

        subs = elem.getElementNames;
        for j = 1:numel(subs)
            subName = subs{j};
            sub     = elem.getElement(subName);
            if strcmp(subName, prefix)
                continue; % avoid self-reference
            end
            addElem_safe(m, sub, sprintf('%s/%s', prefix, subName), depth+1, visited);
        end
    end
end

function y = inferYLabel(name)
% Guess a sensible y-axis label from signal name
    n = lower(name);
    if contains(n,'pressure')
        y = 'mmHg';
    elseif contains(n,'flow')
        y = 'mL/s';          % cm^3/s ≈ mL/s
    elseif contains(n,'volume') || contains(n,'volumeint')
        y = 'mL';
    elseif contains(n,{'hr','heart rate'})
        y = 'bpm';
    elseif contains(n,{'resistance',' r'})
        y = 'mmHg·s/mL';
    elseif contains(n,{'compliance',' c'})
        y = 'mL/mmHg';
    else
        y = 'Value';
    end
end

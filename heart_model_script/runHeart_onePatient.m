%% runHeart_onePatient.m
% Single-patient run for the Simscape Cardiovascular model
% 1) Opens project & loads defaults
% 2) Reads one patient row from CSV
% 3) Applies minimal, documented parameter mapping
% 4) Simulates ~2 beats
% 5) Plots key signals (one figure per signal) + prints SV/CO/AoP

clear; clc;

%% --- Robust project open (no cd required) ---
scriptDir = fileparts(mfilename('fullpath'));           % .../Scripts/Work
projRoot  = fileparts(fileparts(scriptDir));            % go up twice → project root
projPath  = fullfile(projRoot, 'HeartModel.prj');
assert(isfile(projPath), "HeartModel.prj not found at %s", projPath);
proj = openProject(projPath);

% Load default initialization file
run(fullfile(proj.RootFolder, "Scripts", "Initialization.m"));

%% --- User inputs ---
infile       = fullfile(proj.RootFolder, 'choc-data-all.csv');
patientIndex = 1;   % <--- change this as needed

%% --- Load data ---
T = readtable(infile, 'PreserveVariableNames', true);


% Helper to pull a value safely from table (by original column name)
BSA     = getv(T, 'BSA (m2)',                      patientIndex, getv(T,'BSA',patientIndex, 1.7));
HR      = getv(T, 'HR',                             patientIndex, 75);
LVEDVi  = getv(T, 'LVEDVi (mL/m2)',                 patientIndex, getv(T,'LVEDVi',patientIndex, NaN));
LVESVi  = getv(T, 'LVESVi (mL/m2)',                 patientIndex, getv(T,'LVESVi',patientIndex, NaN));
RVEDVi  = getv(T, 'RVEDVi (mL/m2)',                 patientIndex, getv(T,'RVEDVi',patientIndex, NaN));
RVESVi  = getv(T, 'RVESVi (mL/m2)',                 patientIndex, getv(T,'RVESVi',patientIndex, NaN));
SBP     = getv(T, 'SBP',                            patientIndex, NaN);
DBP     = getv(T, 'DBP',                            patientIndex, NaN);
HI      = getv(T, 'Mean HI',                        patientIndex, 2.5);
IVCraw  = getv(T, 'IVC compression?',               patientIndex, 0);
RVraw   = getv(T, 'RV compression?',                patientIndex, 0);

% Normalize compression flags to logical
IVCcomp = asFlag(IVCraw);
RVcomp  = asFlag(RVraw);

%% --- Minimal best-guess mapping (documented) ---

% 1) Initial volumes (from indexed volumes)
if ~isnan(LVEDVi) && ~isnan(LVESVi) && ~isnan(BSA)
    LVEDV = LVEDVi * BSA;           % mL
    LVESV = LVESVi * BSA;           % mL
    assignin('base','X120', LVEDV); % initial LV volume
end
if ~isnan(RVEDVi) && ~isnan(BSA)
    RVEDV = RVEDVi * BSA;           % mL
    assignin('base','X60', RVEDV);  % initial RV volume
end

% 2) Timing from HR (don't touch L1–L4)
if ~isnan(HR) && HR > 0
    assignin('base','HeartRate', HR);
    tc = 60/HR; ts = 0.16 + 0.3*tc;
    assignin('base','tc', tc);
    assignin('base','ts', ts);
else
    tc = evalin('base','tc');   % from defaults
end

% 3) Optional arterial compliance scaling via SV/PP if BP + LV volumes exist
if ~isnan(SBP) && ~isnan(DBP) && exist('LVEDV','var') && exist('LVESV','var')
    PP   = max(5, SBP - DBP);               % mmHg
    SVlv = max(1, LVEDV - LVESV);           % mL
    Cart = SVlv / PP;                       % mmHg^-1·cm^3 (mL ≈ cm^3)
    C1 = evalin('base','C1'); C2 = evalin('base','C2');
    frac = C1 / (C1 + C2 + eps);            % keep C1:C2 ratio
    assignin('base','C1', frac*Cart);
    assignin('base','C2', (1-frac)*Cart);
end

% 4) Thoracic/venous & pulmonary compliance scaling (HI-based)
%    Strongest on C3–C5; mild on C6. Simple convex scaler:
mult = 1.0;
if ~isnan(HI)
    % Map HI=2.5 -> 1.0, HI=12 -> ~0.5 (adjust slope as you like)
    mult = max(0.5, 1 - 0.06*(HI - 2.5));
end
C3 = evalin('base','C3'); C4 = evalin('base','C4'); C5 = evalin('base','C5'); C6 = evalin('base','C6');
assignin('base','C3', C3*(0.85*mult + 0.15));
assignin('base','C4', C4*mult);
assignin('base','C5', C5*mult);
assignin('base','C6', C6*(0.9*mult + 0.1));

% 5) Loop resistances (non-valvular) tweaks based on compression flags
if IVCcomp
    assignin('base','R3', 1.2 * evalin('base','R3'));  % harder systemic venous return
    assignin('base','C3', 0.9 * evalin('base','C3'));  % less venous compliance
end
if RVcomp
    assignin('base','R6', 1.2 * evalin('base','R6'));  % ↑ pulmonary arteriolar load
    assignin('base','C5', 0.9 * evalin('base','C5'));  % ↓ pulmonary arterial compliance
end
% Keep valve Rs (R1,R4,R5,R8) and inertances L1–L4 at defaults.

%% --- Simulate (~2 beats) ---
mdlPath = fullfile(proj.RootFolder, "Models", "CardioVascularSystem.slx");
load_system(mdlPath);
set_param('CardioVascularSystem','SignalLogging','on','StopTime', num2str(2*tc));
out = sim('CardioVascularSystem');

%% --- Plot key signals (one figure per signal) ---
names = out.logsout.getElementNames;
want  = {'Aortic Pressure','Left Ventricular Pressure','Right Venous Atrial Pressure', ...
         'Pulmonary Pressure','LVOF','RVOF','LVIF','RVIF'};
want  = want(ismember(want, names));

for k = 1:numel(want)
    ts = out.logsout.getElement(want{k}).Values;
    figure; plot(ts.Time, ts.Data); grid on
    title(want{k},'Interpreter','none'); xlabel('s');
    if contains(want{k},'Pressure','ignorecase',true), ylabel('mmHg'); else, ylabel('cm^3/s'); end
end

%% --- Quick metrics (last beat, no toolboxes) ---
if all(ismember({'Left Ventricular Pressure','Aortic Pressure'}, names))
    lvp = out.logsout.getElement('Left Ventricular Pressure').Values;
    ap  = out.logsout.getElement('Aortic Pressure').Values;

    % Use last cardiac period based on HR (no findpeaks needed)
    HR_base = evalin('base','HeartRate');
    tc_base = 60 / HR_base;                         % seconds/beat
    t1 = lvp.Time(end);                             % end time
    t0 = max(lvp.Time(1), t1 - tc_base);            % start of last beat
    idx = (lvp.Time >= t0) & (lvp.Time <= t1);      % indices for last beat
    if nnz(idx) < 3
        % Fallback: use last half-second if sampling very short
        t0 = max(lvp.Time(1), t1 - 0.5);
        idx = (lvp.Time >= t0) & (lvp.Time <= t1);
    end

    % Stroke volume and cardiac output if LVOF logged
    SV = NaN; CO = NaN;
    if any(strcmp('LVOF', names))
        lvof = out.logsout.getElement('LVOF').Values;
        SV   = trapz(lvof.Time(idx), lvof.Data(idx));    % mL/beat
        CO   = SV * HR_base / 1000;                      % L/min
    end

    SBP = max(ap.Data(idx)); 
    DBP = min(ap.Data(idx));
    fprintf('SV=%.1f mL, CO=%.2f L/min, AoP≈%.0f/%.0f mmHg (SBP/DBP)\n', SV, CO, SBP, DBP);
end

disp('Run complete. Adjust mapping constants as needed and re-run.');

%% ===== Local helper functions =====
function v = getv(T, name, idx, def)
% Safe getter from table T for column "name" and row idx; falls back to def if
% column is missing or the value is missing.
    if any(strcmp(name, T.Properties.VariableNames))
        v = T.(name)(idx);
        if ismissing(v) || (isnumeric(v) && isempty(v))
            v = def;
        end
    else
        v = def;
    end
end

function tf = asFlag(x)
% Convert numeric/string/logical table entries into logical flags.
    if islogical(x), tf = x; return; end
    try
        if isnumeric(x), tf = x > 0; return; end
        s = upper(string(x));
        tf = ismember(s, ["Y","YES","TRUE","1"]);
    catch
        tf = false;
    end
end

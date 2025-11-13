%% runHeart_compareOne.m
% Healthy (defaults) vs Patient (by Pt Key) on the Simscape Heart model
% Patient mapping is identical to runHeart_onePatient (blocks 1–12).

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

%% --- Read table (first row = header, preserve exact names) ---
T = readtable(infile, 'PreserveVariableNames', true);

%% --- Select patient by Pt Key (safer than raw row index) ---
ptKeyValue = 3;      % <— change this to choose another patient

vars      = string(T.Properties.VariableNames);
varsTrim  = strtrim(vars);
varsLower = lower(varsTrim);

% Try common patterns first, then loose "pt" + "key" match
maskExact = (varsTrim == "Pt Key") | (varsTrim == "PtKey") | (varsTrim == "Pt_Key");
maskLoose = contains(varsLower,"pt") & contains(varsLower,"key");

mask = maskExact | maskLoose;

if ~any(mask)
    error('Could not find a "Pt Key"-like column. Available columns:\n%s', ...
          strjoin(vars, ', '));
end

ptKeyCol = char(vars(find(mask,1)));   % first matching column

ix = find(T.(ptKeyCol) == ptKeyValue, 1);
assert(~isempty(ix), 'No row found for %s = %d', ptKeyCol, ptKeyValue);
fprintf('Using row %d for %s = %g\n', ix, ptKeyCol, ptKeyValue);

%% ---------- 1. PULL CORE FIELDS FROM CHOC TABLE ----------
% (IDENTICAL logic to runHeart_onePatient, just using ix instead of patientIndex)

BSA        = getv(T, 'BSA (m2)',            ix, getv(T,'BSA',ix, 1.7));
HRmax      = getv(T, 'HR max',              ix, NaN);
HRmaxPct   = getv(T, 'HR max %predicted',   ix, NaN);
age        = getv(T, 'Age',                 ix, 16);   % reasonable teen default

LVEDVi     = getv(T, 'LVEDVi (mL/m2)',      ix, getv(T,'LVEDVi', ix, NaN));
LVESVi     = getv(T, 'LVESVi (mL/m2)',      ix, getv(T,'LVESVi', ix, NaN));
RVEDVi     = getv(T, 'RVEDVi (mL/m2)',      ix, getv(T,'RVEDVi', ix, NaN));
RVESVi     = getv(T, 'RVESVi (mL/m2)',      ix, getv(T,'RVESVi', ix, NaN));

SBP        = getv(T, 'SBP',                 ix, NaN);
DBP        = getv(T, 'DBP',                 ix, NaN);
HI         = getv(T, 'Mean HI',             ix, 2.5);

IVCraw     = getv(T, 'IVC compression?',    ix, 0);
RVraw      = getv(T, 'RV compression?',     ix, 0);

% Normalize compression flags to logical
IVCcomp    = asFlag(IVCraw);
RVcomp     = asFlag(RVraw);

%% ---------- 2. EXTRA FIELDS FOR R1/R4/R5/R6/RL/RR MAPPING ----------
% (Same patterns as onePatient / allPatients)

LVEF        = getvFlex(T, {'LVEF','LVEF%','LV EF %'},                       ix, NaN);
RVEF        = getvFlex(T, {'RVEF','RVEF%','RV EF %'},                       ix, NaN);
LVmassIdx   = getvFlex(T, {'LV mass index','LV Mass Index'},               ix, NaN);
Eesep       = getvFlex(T, {'E/e'' ratio (MV septal)','E/e septal','E/e'''}, ix, NaN);
O2PulsePct  = getvFlex(T, {'O2 Pulse %predicted','O2 pulse % predicted'},   ix, NaN);
VO2maxPct   = getvFlex(T, {'VO2 max %predicted','VO2max %predicted'},       ix, NaN);
CCI         = getvFlex(T, {'CCI','PMC'},                                   ix, NaN);
SternalTor  = getvFlex(T, {'Sternal Torsion Angle','Sternal torsion'},     ix, NaN);
RA_size     = getvFlex(T, {'RA size','RA area','RA volume'},               ix, NaN);
LA_size     = getvFlex(T, {'LA size','LA area','LA volume'},               ix, NaN);

%% ---------- 3. HEART RATE FROM HRmax / HRmax %PRED ----------
% (Same heuristic as runHeart_onePatient)
if ~isnan(HRmax)
    HR = 0.6 * HRmax;
elseif ~isnan(HRmaxPct)
    HRpredMax = 220 - age;
    HR = 0.6 * (HRmaxPct/100) * HRpredMax;
else
    HR = 75;   % hard fallback if nothing is available
end

HR_pat = HR;

fprintf('Patient PtKey=%g → HR≈%.1f bpm, BSA=%.2f, HI=%.2f\n', ...
        ptKeyValue, HR_pat, BSA, HI);

%% ---------- RUN 1: HEALTHY (defaults) ----------
% Load pristine defaults
run(fullfile(proj.RootFolder,'Scripts','Initialization.m'));

% Use patient HR so time axes match, but keep other params as "healthy"
assignin('base','HeartRate', HR_pat);
tc_healthy = 60/HR_pat;
ts_healthy = 0.16 + 0.3*tc_healthy;
assignin('base','tc', tc_healthy);
assignin('base','ts', ts_healthy);

% Simulate ~2 beats
set_param(mdlName,'SignalLogging','on','StopTime', num2str(2*tc_healthy));
outHealthy = sim(mdlName);

% Grab a couple of reference signals (optional sanity checks)
lvVolH  = tryGetVals(outHealthy,'VolumeInt_Left');   %#ok<NASGU>
lvofH   = tryGetVals(outHealthy,'LVOF');             %#ok<NASGU>

%% ---------- RUN 2: PATIENT (MAPPED IDENTICALLY TO runHeart_onePatient) ----------
% Reload defaults, then apply mapping blocks 4–12 exactly as in onePatient
run(fullfile(proj.RootFolder,'Scripts','Initialization.m'));

%% ---------- 4. MAP TO MODEL: INITIAL VOLUMES ----------
% X120 — initial LV volume, X60 — initial RV volume
if ~isnan(LVEDVi) && ~isnan(LVESVi) && ~isnan(BSA)
    LVEDV = LVEDVi * BSA;           % mL
    LVESV = LVESVi * BSA;           % mL
    assignin('base','X120', LVEDV); % initial LV volume
else
    LVEDV = NaN; LVESV = NaN;
end

if ~isnan(RVEDVi) && ~isnan(BSA)
    RVEDV = RVEDVi * BSA;           % mL
    assignin('base','X60', RVEDV);  % initial RV volume
else
    RVEDV = NaN;
end

%% ---------- 5. HEART TIMING (HR → tc, ts) ----------
% Don't touch L1–L4 (inertances)
if ~isnan(HR_pat) && HR_pat > 0
    assignin('base','HeartRate', HR_pat);
    tc_patient = 60/HR_pat; 
    ts_patient = 0.16 + 0.3*tc_patient;
    assignin('base','tc', tc_patient);
    assignin('base','ts', ts_patient);
else
    tc_patient = evalin('base','tc');   % from defaults
end

%% ---------- 6. ARTERIAL COMPLIANCE (C1, C2) FROM LV VOLUMES + BP ----------
% Use SV/PP heuristic if we have LVEDV/LVESV + SBP/DBP
if ~isnan(SBP) && ~isnan(DBP) && ~isnan(LVEDV) && ~isnan(LVESV)
    PP   = max(5, SBP - DBP);               % mmHg
    SVlv = max(1, LVEDV - LVESV);           % mL
    Cart = SVlv / PP;                       % mmHg^-1·cm^3 (mL ≈ cm^3)
    C1 = evalin('base','C1'); C2 = evalin('base','C2');
    frac = C1 / (C1 + C2 + eps);            % keep C1:C2 ratio
    assignin('base','C1', frac*Cart);
    assignin('base','C2', (1-frac)*Cart);
end

%% ---------- 7. HI-BASED THORACIC / VENOUS / PULMONARY COMPLIANCE (C3–C6) ----------
% Higher HI → more chest compression → lower venous/pulmonary compliances
mult = 1.0;
if ~isnan(HI)
    % Map HI=2.5 -> 1.0, HI=12 -> ~0.5
    mult = max(0.5, 1 - 0.06*(HI - 2.5));
end
C3 = evalin('base','C3'); C4 = evalin('base','C4'); 
C5 = evalin('base','C5'); C6 = evalin('base','C6');
assignin('base','C3', C3*(0.85*mult + 0.15));
assignin('base','C4', C4*mult);
assignin('base','C5', C5*mult);
assignin('base','C6', C6*(0.9*mult + 0.1));

%% ---------- 8. LOOP RESISTANCES FROM COMPRESSION FLAGS (R3, R6 + matching C3/C5) ----------
% PE with IVC or RV compression → harder venous return + higher pulmonary vascular resistance
if IVCcomp
    assignin('base','R3', 1.2 * evalin('base','R3'));  % harder systemic venous return
    assignin('base','C3', 0.9 * evalin('base','C3'));  % less venous compliance
end
if RVcomp
    assignin('base','R6', 1.2 * evalin('base','R6'));  % ↑ pulmonary arteriolar load
    assignin('base','C5', 0.9 * evalin('base','C5'));  % ↓ pulmonary arterial compliance
end

%% ---------- 9. VALVE RESISTANCES (R1, R4, R5, R8) FROM TABLE HEURISTICS ----------
% R1: Aortic valve – use LV systolic function (LVESVi/LVEF) as a proxy
try
    if ~isnan(LVESVi) && ~isnan(LVEF)
        R1_0 = evalin('base','R1');
        % Higher LVESVi with low LVEF → worse forward ejection → slightly higher R1
        % Normalize: LVESVi ~ 30–80, LVEF ~ 35–65
        loadFactor = clamp01((LVESVi - 40) / 40);       % 0 @ 40, ~1 @ 80
        efFactor   = clamp01((55 - LVEF) / 20);         % 0 @ 55, ~1 @ 35
        facR1      = 1 + 0.3*(0.6*loadFactor + 0.4*efFactor);   % up to ~30% increase
        assignin('base','R1', R1_0 * facR1);
    end
catch
    % If R1 not present, silently skip
end

% R4, R5: Valve-level effects, strongly tied to sternal torsion, PMC/CCI, RV compression
try
    R4_0 = evalin('base','R4');
    R5_0 = evalin('base','R5');
    facValves = 1.0;

    % CCI / PMC = 2 or 3 → more severe concavity
    if ~isnan(CCI) && CCI >= 2
        facValves = facValves * (1 + 0.25 * clamp01((CCI - 2) / 2));  % up to ~25% ↑
    end

    % Sternal torsion angle – large angles → more twist on RV outflow / pulmonary valve
    if ~isnan(SternalTor)
        facValves = facValves * (1 + 0.3 * clamp01((SternalTor - 15) / 20)); % 0 @ 15°, +30% @ ~35°
    end

    % RV compression flag – direct compression of RVOT / pulmonary valve
    if RVcomp
        facValves = facValves * 1.2;
    end

    facValves = min(max(facValves, 0.7), 2.0);  % safety bounds
    assignin('base','R4', R4_0 * facValves);
    assignin('base','R5', R5_0 * facValves);
catch
    % If any of these params missing, skip
end

% R8: Mitral valve – keep tied mainly to LV filling pressure (E/e'), but small effect
try
    if ~isnan(Eesep)
        R8_0 = evalin('base','R8');
        % high E/e' → higher filling pressure → slightly higher R8
        eeFactor = clamp01((Eesep - 10) / 15);     % 0 @10, ~1 @25
        facR8    = 1 + 0.2 * eeFactor;
        assignin('base','R8', R8_0 * facR8);
    end
catch
end

%% ---------- 10. R6 (PULMONARY RESISTANCE) FROM RVEF / VO2max ----------
% Additional scaling beyond RV compression, based on RV performance
try
    R6_0 = evalin('base','R6');
    fac6 = 1.0;

    if ~isnan(RVEF)
        % Low RVEF → more pulmonary afterload
        efPulm = clamp01((55 - RVEF) / 20);      % 0 @55, ~1 @35
        fac6   = fac6 * (1 + 0.3 * efPulm);
    end

    if ~isnan(VO2maxPct)
        % Low VO2max %pred → more global cardiorespiratory limitation
        vo2Bad = clamp01((100 - VO2maxPct) / 40);  % 0 @100, ~1 @60
        fac6   = fac6 * (1 + 0.2 * vo2Bad);
    end

    fac6 = min(max(fac6, 0.7), 2.5);
    assignin('base','R6', R6_0 * fac6);
catch
end

%% ---------- 11. MYOCARDIAL VISCOUS TERMS (RL, RR) ----------
% RL: LV "stiffness" – E/e', LV mass index, O2 Pulse %pred
try
    RL0 = evalin('base','RL');
    facRL = 1.0;

    if ~isnan(Eesep)
        stiffLV = clamp01((Eesep - 10) / 15);       % high E/e' = stiff LV
        facRL   = facRL * (1 + 0.3 * stiffLV);
    end

    if ~isnan(LVmassIdx)
        hyperLV = clamp01((LVmassIdx - 80) / 60);   % higher LVMI → hypertrophy
        facRL   = facRL * (1 + 0.3 * hyperLV);
    end

    if ~isnan(O2PulsePct)
        lowO2P  = clamp01((100 - O2PulsePct) / 40); % low O2 pulse %pred → inefficient stroke work
        facRL   = facRL * (1 + 0.3 * lowO2P);
    end

    facRL = min(max(facRL, 0.7), 3.0);
    assignin('base','RL', RL0 * facRL);
catch
end

% RR: RV "stiffness" – RVEF%, O2 Pulse %pred
try
    RR0 = evalin('base','RR');
    facRR = 1.0;

    if ~isnan(RVEF)
        stiffRV = clamp01((55 - RVEF) / 20);        % lower RVEF → stiffer/less efficient RV
        facRR   = facRR * (1 + 0.3 * stiffRV);
    end

    if ~isnan(O2PulsePct)
        lowO2P  = clamp01((100 - O2PulsePct) / 40);
        facRR   = facRR * (1 + 0.25 * lowO2P);
    end

    facRR = min(max(facRR, 0.7), 3.0);
    assignin('base','RR', RR0 * facRR);
catch
end

%% ---------- 12. OPTIONAL: R7 (PULMONARY VENOUS SIDE) FROM E/e' + LA size ----------
try
    if ~isnan(Eesep) || ~isnan(LA_size)
        R7_0 = evalin('base','R7');
        fac7 = 1.0;
        if ~isnan(Eesep)
            highLVfill = clamp01((Eesep - 10) / 15);
            fac7 = fac7 * (1 + 0.25 * highLVfill);
        end
        if ~isnan(LA_size)
            bigLA = clamp01((LA_size - 25) / 20);  % very rough scaling
            fac7 = fac7 * (1 + 0.2 * bigLA);
        end
        fac7 = min(max(fac7, 0.7), 2.5);
        assignin('base','R7', R7_0 * fac7);
    end
catch
end

%% ---------- SIMULATE PATIENT (~2 beats) ----------
set_param(mdlName,'SignalLogging','on','StopTime', num2str(2*tc_patient));
outPatient = sim(mdlName);

% Grab signals (optional)
lvVolP = tryGetVals(outPatient,'VolumeInt_Left'); %#ok<NASGU>
lvofP  = tryGetVals(outPatient,'LVOF');           %#ok<NASGU>

%% ---------- PLOT EVERYTHING (HEALTHY vs PATIENT) ----------
mapH = flattenLogs_safe(outHealthy.logsout);
mapP = flattenLogs_safe(outPatient.logsout);

onlyGroups = true;
press = {'Aortic Pressure','Left Ventricular Pressure','Right Venous Atrial Pressure','Pulmonary Pressure','PiLa(t)','Pv'};
flows = {'LVOF','LVIF','RVOF','RVIF','LeftVentricleFlow'};
voles = {'VolumeInt','VolumeInt_Left','EL(t)'};
curated = [press, flows, voles];

kH = string(keys(mapH));
kP = string(keys(mapP));

if onlyGroups
    curatedStr = string(curated);
    namesCommon = curatedStr(ismember(curatedStr, intersect(kH, kP)));
else
    namesCommon = intersect(kH, kP);
end

namesCommon = sort(namesCommon);

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

%% ===== Local helper functions =====
function v = getv(T, name, idx, def)
% Safe getter from table T for column "name" and row idx; falls back to def.
% - Unwraps cell arrays
% - Converts numeric-looking text to numbers
% - Leaves true text (like 'Y'/'N') alone for asFlag()

    v = def;

    if ~any(strcmp(name, T.Properties.VariableNames))
        return;  % column not found → def
    end

    col = T.(name);

    if idx > height(T)
        return;  % out of range → def
    end

    val = col(idx);

    % unwrap cellstr
    if iscell(val) && ~isempty(val)
        val = val{1};
    end

    % Missing or empty numeric → def
    if ismissing(val) || (isnumeric(val) && isempty(val))
        v = def;
        return;
    end

    % If already numeric, keep it
    if isnumeric(val)
        v = val;
        return;
    end

    % For char/string: try to parse as a number
    s = string(val);
    num = str2double(s);

    if ~isnan(num)
        % e.g. '120' → 120
        v = num;
        return;
    else
        % Non-numeric text like 'Y', 'N', etc. → keep original
        v = val;
        return;
    end
end


function v = getvFlex(T, patterns, idx, def)
% Get value from the first column whose name == or contains any pattern.
% Returns def if not found or unusable.
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
                if iscell(val), val = val{1}; end
                if isnumeric(val)
                    if ~(isnan(val) || isempty(val))
                        v = val;
                        return;
                    end
                else
                    num = str2double(string(val));
                    if ~isnan(num)
                        v = num;
                        return;
                    else
                        v = def;
                        return;
                    end
                end
            end
        end
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

function y = clamp01(x)
% Clamp to [0, 1]
    y = min(max(x,0),1);
end

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

    cls   = class(elem);
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

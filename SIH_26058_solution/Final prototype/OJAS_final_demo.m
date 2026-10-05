function results = OJAS_random_ocean_waveform_10s(oceanFile, sensorLutFile, waveformLutFile)
% OJAS_RANDOM_OCEAN_WAVEFORM_10S
% =========================================================================
% Random 10-second OJAS waveform demonstration.
%
% Every 10 seconds:
%   1) Randomly selects one row from the first 1800 rows of ocean_data.csv.
%   2) Reads depth, temperature, salinity, turbidity and Mackenzie speed.
%   3) Finds the unique Wxx using the supplied sensor/Mackenzie LUT.
%   4) Reads the selected waveform definition from the supplied waveform LUT.
%   5) Synthesizes that waveform exactly from the CSV parameters.
%   6) Updates the GUI with the environment, Wxx, waveform, FFT and IF/phase
%      diagnostics.
%
% IMPORTANT:
%   - No Wxx mapping is hardcoded.
%   - No waveform parameters are hardcoded.
%   - No Barker sequence is hardcoded.
%   - All mapping and waveform definitions come from the supplied CSV files.
%   - The demonstration is driven by the supplied ocean rows.
%
% Usage:
%   OJAS_random_ocean_waveform_10s(...)
%
% Or simply:
%   OJAS_random_ocean_waveform_10s
%
% Default file names:
%   ocean_data.csv
%   OJAS_FINAL_SENSOR_MACKENZIE_LUT_24.csv
%   OJAS_final_waveform_library_24_Barker.csv
%
% The first 1800 ocean rows are used as the demonstration pool.
% A random row is displayed immediately, then another random row every 10 s.
%
% =========================================================================

clc;

%% --------------------------- FILE INPUT ---------------------------------
if nargin < 1 || isempty(oceanFile)
    oceanFile = pickCsvOrDefault( ...
        'ocean_data.csv', ...
        'Select ocean_data.csv');
end

if nargin < 2 || isempty(sensorLutFile)
    sensorLutFile = pickCsvOrDefault( ...
        'OJAS_FINAL_SENSOR_MACKENZIE_LUT_24.csv', ...
        'Select OJAS sensor/Mackenzie LUT CSV');
end

if nargin < 3 || isempty(waveformLutFile)
    waveformLutFile = pickCsvOrDefault( ...
        'OJAS_final_waveform_library_24_Barker.csv', ...
        'Select OJAS waveform library CSV');
end

ocean  = readtable(oceanFile,       'VariableNamingRule','preserve');
sensor = readtable(sensorLutFile,   'VariableNamingRule','preserve');
wave   = readtable(waveformLutFile, 'VariableNamingRule','preserve');

%% --------------------------- SCHEMA CHECK -------------------------------
requiredOcean = { ...
    'depth_m','temperature_C','salinity_PSU','turbidity_NTU', ...
    'sound_speed_mps_mackenzie'};

requiredSensor = { ...
    'waveform_id', ...
    'mackenzie_speed_min_mps','mackenzie_speed_max_mps', ...
    'depth_min_m','depth_max_m', ...
    'temperature_min_C','temperature_max_C', ...
    'salinity_min_PSU','salinity_max_PSU', ...
    'turbidity_min_NTU','turbidity_max_NTU'};

requiredWave = { ...
    'waveform_id','waveform_type','fc_kHz','B_multiplier','Tp_us', ...
    'B_min_Hz','B_Hz','B_kHz','Tp_s','TBP','f_low_Hz','f_high_Hz', ...
    'frequency_valid','sampling_valid','hardware_valid', ...
    'phase_code_family','phase_code_length','phase_code_bpsk', ...
    'phase_code_phase_rad'};

assertRequiredColumns(ocean,requiredOcean,'ocean_data.csv');
assertRequiredColumns(sensor,requiredSensor,'sensor/Mackenzie LUT');
assertRequiredColumns(wave,requiredWave,'waveform library');

sensor.waveform_id = string(sensor.waveform_id);
wave.waveform_id   = string(wave.waveform_id);

%% ----------------------- RANDOMIZATION SETTINGS -------------------------
DEMO_ROWS = min(1800,height(ocean));
UPDATE_PERIOD_S = 10;

if DEMO_ROWS < 1
    error('The ocean CSV contains no rows.');
end

% Use first 1800 rows exactly as requested when available.
poolRows = (1:DEMO_ROWS).';

% Analyze which rows have exactly one LUT match.
uniqueMatch = false(DEMO_ROWS,1);
selectedW = strings(DEMO_ROWS,1);

for i = 1:DEMO_ROWS
    c  = numericOrNaN(ocean.sound_speed_mps_mackenzie(i));
    d  = numericOrNaN(ocean.depth_m(i));
    T  = numericOrNaN(ocean.temperature_C(i));
    S  = numericOrNaN(ocean.salinity_PSU(i));
    tu = numericOrNaN(ocean.turbidity_NTU(i));

    valid = ...
        sensor.mackenzie_speed_min_mps <= c & c <= sensor.mackenzie_speed_max_mps & ...
        sensor.depth_min_m <= d & d <= sensor.depth_max_m & ...
        sensor.temperature_min_C <= T & T <= sensor.temperature_max_C & ...
        sensor.salinity_min_PSU <= S & S <= sensor.salinity_max_PSU & ...
        sensor.turbidity_min_NTU <= tu & tu <= sensor.turbidity_max_NTU;

    idx = find(valid);

    if numel(idx) == 1
        uniqueMatch(i) = true;
        selectedW(i) = sensor.waveform_id(idx);
    end
end

matchedPool = poolRows(uniqueMatch);

fprintf('\n============================================================\n');
fprintf('OJAS RANDOM 10-SECOND DEMONSTRATION\n');
fprintf('============================================================\n');
fprintf('Ocean rows available       : %d\n',height(ocean));
fprintf('Rows used in random pool   : %d\n',DEMO_ROWS);
fprintf('Unique LUT-match rows      : %d\n',numel(matchedPool));
fprintf('Update interval            : %g s\n',UPDATE_PERIOD_S);
fprintf('============================================================\n\n');

if isempty(matchedPool)
    error('None of the first %d ocean rows has a unique sensor LUT match.',DEMO_ROWS);
end

%% --------------------------- RESULTS TABLE ------------------------------
results = table();

%% --------------------------- GUI ----------------------------------------
fig = figure( ...
    'Name','OJAS — Random Ocean Row Every 10 Seconds', ...
    'NumberTitle','off', ...
    'Color','w', ...
    'Position',[30 35 1550 900], ...
    'CloseRequestFcn',@closeFigure);

% Control/status bar
uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.010 0.955 0.105 0.030], ...
    'String','Random ocean row:', ...
    'HorizontalAlignment','right', ...
    'FontWeight','bold', ...
    'BackgroundColor','w');

hRow = uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.118 0.955 0.055 0.030], ...
    'String','-', ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold', ...
    'BackgroundColor','w');

uicontrol(fig,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.490 0.952 0.085 0.036], ...
    'String','Random Now', ...
    'Callback',@randomNow);

uicontrol(fig,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.580 0.952 0.085 0.036], ...
    'String','Stop Timer', ...
    'Callback',@stopTimer);

uicontrol(fig,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.670 0.952 0.085 0.036], ...
    'String','Start Timer', ...
    'Callback',@startTimer);

hStatus = uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.765 0.952 0.225 0.036], ...
    'String','Starting...', ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold', ...
    'BackgroundColor','w');

% Layout
axTime = axes('Parent',fig,'Position',[0.350 0.690 0.300 0.235]);
axZoom = axes('Parent',fig,'Position',[0.680 0.690 0.300 0.235]);
axFFT  = axes('Parent',fig,'Position',[0.035 0.085 0.285 0.545]);
axIF   = axes('Parent',fig,'Position',[0.360 0.085 0.285 0.545]);
axErr  = axes('Parent',fig,'Position',[0.680 0.085 0.300 0.545]);

hTable = uitable(fig, ...
    'Units','normalized', ...
    'Position',[0.020 0.690 0.300 0.235], ...
    'ColumnName',{'Parameter','Value'}, ...
    'RowName',[], ...
    'ColumnWidth',{125,325}, ...
    'FontSize',9);

state.currentRow = [];
state.currentW = "";
state.timer = [];
state.lastValidation = "";

% Create timer but start after first display.
state.timer = timer( ...
    'ExecutionMode','fixedRate', ...
    'Period',UPDATE_PERIOD_S, ...
    'BusyMode','drop', ...
    'TimerFcn',@timerTick);

%% --------------------------- FIRST DISPLAY ------------------------------
randomNow();
startTimer();

%% Return handle/results only if requested.
if nargout == 0
    clear results
else
    results = struct();
    results.oceanFile = oceanFile;
    results.sensorLutFile = sensorLutFile;
    results.waveformLutFile = waveformLutFile;
    results.demoRows = DEMO_ROWS;
    results.intervalSeconds = UPDATE_PERIOD_S;
    results.randomPoolRows = poolRows;
    results.uniqueMatchRows = matchedPool;
end

%% ============================== CALLBACKS ===============================
    function timerTick(~,~)
        if ~ishghandle(fig)
            return;
        end
        randomNow();
    end

    function randomNow(~,~)
        if ~ishghandle(fig)
            return;
        end

        % Randomly choose from the requested 1800-row pool.
        % If a selected row has no unique LUT match, retry until a
        % waveform-producing row is found.
        maxAttempts = max(20,2*DEMO_ROWS);
        row = [];
        wID = "";

        for attempt = 1:maxAttempts %#ok<NASGU>
            candidate = poolRows(randi(numel(poolRows)));

            c  = numericOrNaN(ocean.sound_speed_mps_mackenzie(candidate));
            d  = numericOrNaN(ocean.depth_m(candidate));
            T  = numericOrNaN(ocean.temperature_C(candidate));
            S  = numericOrNaN(ocean.salinity_PSU(candidate));
            tu = numericOrNaN(ocean.turbidity_NTU(candidate));

            valid = ...
                sensor.mackenzie_speed_min_mps <= c & c <= sensor.mackenzie_speed_max_mps & ...
                sensor.depth_min_m <= d & d <= sensor.depth_max_m & ...
                sensor.temperature_min_C <= T & T <= sensor.temperature_max_C & ...
                sensor.salinity_min_PSU <= S & S <= sensor.salinity_max_PSU & ...
                sensor.turbidity_min_NTU <= tu & tu <= sensor.turbidity_max_NTU;

            idx = find(valid);

            if numel(idx) == 1
                row = candidate;
                wID = sensor.waveform_id(idx);
                break;
            end
        end

        if isempty(row)
            % Safety fallback: choose a known unique-match row.
            row = matchedPool(randi(numel(matchedPool)));
            wID = selectedW(row);
        end

        state.currentRow = row;
        state.currentW = wID;

        updateDisplay(row,wID);
    end

    function startTimer(~,~)
        if isempty(state.timer) || ~isvalid(state.timer)
            return;
        end

        if strcmp(state.timer.Running,'off')
            start(state.timer);
        end

        set(hStatus,'String','RUNNING — random row every 10 s');
    end

    function stopTimer(~,~)
        if ~isempty(state.timer) && isvalid(state.timer)
            if strcmp(state.timer.Running,'on')
                stop(state.timer);
            end
        end

        set(hStatus,'String','STOPPED');
    end

    function updateDisplay(i,wID)
        cla(axTime);
        cla(axZoom);
        cla(axFFT);
        cla(axIF);
        cla(axErr);

        wi = find(wave.waveform_id == wID,1,'first');

        if isempty(wi)
            clearAxes('Selected Wxx not found in waveform CSV.');
            return;
        end

        wr = wave(wi,:);
        type = toText(wr.waveform_type);

        % ---------- Parameter table ----------
        paramData = { ...
            'Ocean row',sprintf('%d / %d',i,height(ocean)); ...
            'Depth',sprintf('%.6g m',numericOrNaN(ocean.depth_m(i))); ...
            'Temperature',sprintf('%.6g °C',numericOrNaN(ocean.temperature_C(i))); ...
            'Salinity',sprintf('%.6g PSU',numericOrNaN(ocean.salinity_PSU(i))); ...
            'Turbidity',sprintf('%.6g NTU',numericOrNaN(ocean.turbidity_NTU(i))); ...
            'Mackenzie speed',sprintf('%.6g m/s',numericOrNaN(ocean.sound_speed_mps_mackenzie(i))); ...
            'Selected Wxx',char(wID); ...
            'Waveform type',char(type); ...
            'fc',sprintf('%.6g kHz',numericOrNaN(wr.fc_kHz)); ...
            'Bandwidth',sprintf('%.6g kHz',numericOrNaN(wr.B_kHz)); ...
            'Pulse duration',sprintf('%.6g ms',numericOrNaN(wr.Tp_s)*1e3); ...
            'f_low',sprintf('%.6g kHz',numericOrNaN(wr.f_low_Hz)/1e3); ...
            'f_high',sprintf('%.6g kHz',numericOrNaN(wr.f_high_Hz)/1e3); ...
            'TBP',sprintf('%.6g',numericOrNaN(wr.TBP))};

        if type == "Phase_Coded"
            try
                [pr,bpsk,fam] = extractPhaseData(wr);
                paramData(end+1,:) = {'Code family',char(fam)};
                paramData(end+1,:) = {'Code chips',num2str(numel(pr))};
                paramData(end+1,:) = {'BPSK sequence',strjoin(string(bpsk),'  ')};
                paramData(end+1,:) = {'Phase sequence',strjoin(string(pr),'  ')};
            catch
            end
        end

        paramData = normalizeUITableData(paramData);
        set(hTable,'Data',paramData);

        % ---------- Waveform synthesis ----------
        [t,x,fTheory,phaseCycles,phaseOffset,chipEdges,meta,msg] = ...
            synthesizeWaveform(wr);

        %#ok<ASGLU>
        if isempty(t)
            clearAxes(msg);
            set(hStatus,'String',sprintf('Row %d | %s | ERROR',i,char(wID)));
            return;
        end

        Tpulse = t(end);
        TpulseUs = Tpulse*1e6;

        % ---------- IF diagnostics ----------
        edgeN = max(10,round(0.05*numel(t)));
        validCore = false(size(t));

        if 2*edgeN < numel(t)
            validCore(edgeN+1:end-edgeN) = true;
        else
            validCore(:) = true;
        end

        if type == "Phase_Coded"
            fActual = numericOrNaN(wr.fc_kHz)*1e3*ones(size(t));
            validation = validatePhaseWaveform(wr,fTheory);
        else
            fActual = estimateInstantaneousFrequency(x,t);
            validation = validateFrequencyWaveform(fTheory,fActual,validCore);
        end

        fActualPlot = fActual;
        fActualPlot(~validCore) = NaN;

        ifErrorPlot = fActual-fTheory;
        ifErrorPlot(~validCore) = NaN;

        state.lastValidation = validation;

        % ---------- Time domain ----------
        p = displayIndices(numel(t),9000);
        plot(axTime,t(p)*1e6,x(p),'LineWidth',0.8);
        grid(axTime,'on');
        xlabel(axTime,'Time (\mus)');
        ylabel(axTime,'Amplitude');
        ylim(axTime,[-1.2 1.2]);
        xlim(axTime,[0 TpulseUs]);
        title(axTime,sprintf('TIME DOMAIN — %s | %s',char(wID),char(type)), ...
            'Interpreter','none');

        if ~isempty(chipEdges)
            hold(axTime,'on');
            for k = 2:numel(chipEdges)-1
                xline(axTime,chipEdges(k)*1e6,'--','LineWidth',0.8);
            end
            hold(axTime,'off');
        end

        % ---------- Zoom ----------
        zoomUs = chooseZoom(type,wr,TpulseUs);
        maskZ = t*1e6 <= zoomUs;

        if ~any(maskZ)
            maskZ = true(size(t));
        end

        tz = t(maskZ);
        xz = x(maskZ);
        pz = displayIndices(numel(tz),7500);

        plot(axZoom,tz(pz)*1e6,xz(pz),'LineWidth',0.9);
        grid(axZoom,'on');
        xlabel(axZoom,'Time (\mus)');
        ylabel(axZoom,'Amplitude');
        ylim(axZoom,[-1.2 1.2]);
        xlim(axZoom,[0,min(zoomUs,TpulseUs)]);
        title(axZoom,sprintf('ZOOMED — %.4g \\mus',min(zoomUs,TpulseUs)));

        if ~isempty(chipEdges)
            hold(axZoom,'on');
            for k = 2:numel(chipEdges)-1
                ek = chipEdges(k)*1e6;
                if ek <= zoomUs
                    xline(axZoom,ek,'--','LineWidth',0.8);
                end
            end
            hold(axZoom,'off');
        end

        % ---------- FFT ----------
        [fFFT,magDb] = waveformSpectrum(t,x);

        fCenter = numericOrNaN(wr.fc_kHz)*1e3;
        B = numericOrNaN(wr.B_Hz);
        if ~isfinite(B) || B <= 0
            B = max(1,0.02*fCenter);
        end

        fLow = numericOrNaN(wr.f_low_Hz);
        fHigh = numericOrNaN(wr.f_high_Hz);
        margin = max(0.40*B,0.008*fCenter);

        keep = fFFT >= max(0,fLow-margin) & ...
               fFFT <= fHigh+margin;

        plot(axFFT,fFFT(keep)/1e3,magDb(keep),'LineWidth',1.1);
        grid(axFFT,'on');
        xlabel(axFFT,'Frequency (kHz)');
        ylabel(axFFT,'Magnitude (dB)');
        title(axFFT,'FREQUENCY DOMAIN — ACTUAL FFT');

        if any(keep)
            xlim(axFFT,[max(0,fLow-margin),fHigh+margin]/1e3);
        end

        hold(axFFT,'on');
        xline(axFFT,fCenter/1e3,'--','LineWidth',0.9);
        xline(axFFT,fLow/1e3,':','LineWidth',0.8);
        xline(axFFT,fHigh/1e3,':','LineWidth',0.8);
        hold(axFFT,'off');

        % ---------- IF ----------
        pIF = displayIndices(numel(t),9000);

        plot(axIF,t(pIF)*1e6,fActualPlot(pIF)/1e3, ...
            'LineWidth',1.1,'DisplayName','Actual IF');

        hold(axIF,'on');

        plot(axIF,t(pIF)*1e6,fTheory(pIF)/1e3,'--', ...
            'LineWidth',1.4,'DisplayName','CSV theory');

        xline(axIF,t(edgeN)*1e6,':','LineWidth',0.8, ...
            'DisplayName','Validation edge');

        xline(axIF,t(end-edgeN)*1e6,':','LineWidth',0.8, ...
            'HandleVisibility','off');

        hold(axIF,'off');

        grid(axIF,'on');
        xlabel(axIF,'Time (\mus)');
        ylabel(axIF,'Frequency (kHz)');
        title(axIF,'INSTANTANEOUS FREQUENCY — ACTUAL vs CSV (5–95%)');
        legend(axIF,'Location','southoutside','Orientation','horizontal');

        if isfinite(fLow) && isfinite(fHigh)
            marginIF = max(0.12*abs(fHigh-fLow),0.008*fCenter);
            if abs(fHigh-fLow) > 0
                ylim(axIF,[(fLow-marginIF)/1e3,(fHigh+marginIF)/1e3]);
            else
                ylim(axIF,[fCenter/1e3-1,fCenter/1e3+1]);
            end
        end

        % ---------- Error / phase ----------
        if type == "Phase_Coded"
            [phaseRad,bpsk,fam] = extractPhaseData(wr);
            edgesUs = chipEdges*1e6;

            stairs(axErr,edgesUs,[phaseRad phaseRad(end)], ...
                'LineWidth',2.0,'DisplayName','CSV phase');

            hold(axErr,'on');
            for k = 2:numel(edgesUs)-1
                xline(axErr,edgesUs(k),'--','LineWidth',0.8);
            end
            hold(axErr,'off');

            grid(axErr,'on');
            xlabel(axErr,'Time (\mus)');
            ylabel(axErr,'Phase offset (rad)');
            title(axErr,sprintf('PHASE CODE — %s',char(fam)), ...
                'Interpreter','none');
            xlim(axErr,[0 TpulseUs]);

            minPhase = min([0;phaseRad(:)])-0.4;
            maxPhase = max([pi;phaseRad(:)])+0.4;
            ylim(axErr,[minPhase,maxPhase]);
            yticks(sort(unique([0 pi])));
            yticklabels({'0','\pi'});

            legend(axErr,sprintf('BPSK: [%s]',strjoin(string(bpsk),' ')), ...
                'Location','southoutside');
        else
            plot(axErr,t(pIF)*1e6,ifErrorPlot(pIF), ...
                'LineWidth',1.0,'DisplayName','Actual - CSV theory');

            hold(axErr,'on');
            yline(axErr,0,'--','LineWidth',0.9,'DisplayName','Zero error');
            hold(axErr,'off');

            grid(axErr,'on');
            xlabel(axErr,'Time (\mus)');
            ylabel(axErr,'Frequency error (Hz)');
            title(axErr,'FREQUENCY ERROR — CENTRAL 90% ONLY');
            legend(axErr,'Location','southoutside','Orientation','horizontal');

            e = fActual(validCore)-fTheory(validCore);
            e = e(isfinite(e));

            if isempty(e)
                scale = 25;
            else
                coreMax = max(abs(e));
                coreRms = sqrt(mean(e.^2));
                scale = max(25,1.35*max(coreMax,3*coreRms));
            end

            ylim(axErr,[-scale,scale]);
        end

        % ---------- Status ----------
        set(hRow,'String',num2str(i));

        set(hStatus,'String',sprintf( ...
            'RUNNING | %s | %s | fc %.6g kHz | B %.6g kHz', ...
            char(wID),char(type), ...
            numericOrNaN(wr.fc_kHz),numericOrNaN(wr.B_kHz)));


        drawnow;
    end

    function closeFigure(~,~)
        try
            if ~isempty(state.timer) && isvalid(state.timer)
                stop(state.timer);
                delete(state.timer);
            end
        catch
        end
        delete(fig);
    end

end

%% =========================================================================
% WAVEFORM SYNTHESIS
% =========================================================================
function [t,x,fTheory,phaseCycles,phaseOffset,chipEdges,meta,msg] = ...
    synthesizeWaveform(wr)

type = toText(wr.waveform_type);

fc = numericOrNaN(wr.fc_kHz)*1e3;
fLow = numericOrNaN(wr.f_low_Hz);
fHigh = numericOrNaN(wr.f_high_Hz);
Tp = numericOrNaN(wr.Tp_s);

t = [];
x = [];
fTheory = [];
phaseCycles = [];
phaseOffset = [];
chipEdges = [];
meta = struct();
msg = '';

if ~isfinite(fc) || fc <= 0
    msg = 'INVALID: fc in CSV';
    return;
end

if ~isfinite(Tp) || Tp <= 0
    msg = 'INVALID: Tp in CSV';
    return;
end

maxF = max([abs(fc),abs(fLow),abs(fHigh)]);
if ~isfinite(maxF) || maxF <= 0
    msg = 'INVALID: frequency data in CSV';
    return;
end

% Same numerical synthesis philosophy as the supplied final debugger.
samplesPerCycle = 32;
Fs = samplesPerCycle*maxF;

N = ceil(Tp*Fs)+1;
if N > 150000
    N = 150001;
end

t = linspace(0,Tp,N).';

switch type

    case "LFM"
        if ~isfinite(fLow) || ~isfinite(fHigh)
            t=[]; msg='INVALID: LFM f_low/f_high'; return;
        end

        k = (fHigh-fLow)/Tp;
        fTheory = fLow + k*t;
        phaseCycles = fLow*t + 0.5*k*t.^2;
        x = cos(2*pi*phaseCycles);
        phaseOffset = zeros(size(t));
        msg = 'LFM_OK';

    case "Geometric_NFM"
        if ~isfinite(fLow) || ~isfinite(fHigh) || ...
                fLow <= 0 || fHigh <= 0
            t=[]; msg='INVALID: Geometric NFM limits'; return;
        end

        a = log(fHigh/fLow)/Tp;

        if abs(a) < eps
            fTheory = fLow*ones(size(t));
            phaseCycles = fLow*t;
        else
            fTheory = fLow*exp(a*t);
            phaseCycles = (fLow/a)*(exp(a*t)-1);
        end

        x = cos(2*pi*phaseCycles);
        phaseOffset = zeros(size(t));
        msg = 'GEOMETRIC_NFM_OK';

    case "Phase_Coded"
        [phaseRad,bpsk,fam] = extractPhaseData(wr);

        if isempty(phaseRad)
            t=[]; msg='INVALID: phase code'; return;
        end

        nChips = numel(phaseRad);
        Tc = Tp/nChips;

        chipIndex = floor(t/Tc)+1;
        chipIndex = max(1,min(nChips,chipIndex));

        phaseOffset = phaseRad(chipIndex);
        chipEdges = (0:nChips)*Tc;

        fTheory = fc*ones(size(t));
        phaseCycles = fc*t + phaseOffset/(2*pi);
        x = cos(2*pi*fc*t + phaseOffset);

        meta.family = fam;
        meta.bpsk = bpsk;
        meta.phaseRad = phaseRad;
        meta.chipDuration = Tc;

        msg = 'PHASE_CODED_OK';

    otherwise
        t=[];
        msg=['INVALID: unsupported waveform type ' char(type)];
end

end

%% =========================================================================
% INSTANTANEOUS FREQUENCY
% =========================================================================
function fInst = estimateInstantaneousFrequency(x,t)

x = x(:);
t = t(:);
N = numel(x);

if N < 32
    fInst = NaN(size(x));
    return;
end

dt = mean(diff(t));
Fs = 1/dt;

X = fft(x);
H = zeros(N,1);

if mod(N,2)==0
    H(1) = 1;
    H(N/2+1) = 1;
    H(2:N/2) = 2;
else
    H(1) = 1;
    H(2:(N+1)/2) = 2;
end

analytic = ifft(X.*H);
phi = unwrap(angle(analytic));

carrierEstimate = max(1,median(abs(diff(phi)))/(2*pi*dt));
W = round(8*Fs/carrierEstimate);
W = max(51,min(401,W));

if W >= N
    W = N - 1;
end

if mod(W,2)==0
    W = W - 1;
end

if W < 5
    W = 5;
end

halfW = floor(W/2);
fInst = NaN(N,1);

for k = (halfW+1):(N-halfW)
    tt = t(k-halfW:k+halfW);
    pp = phi(k-halfW:k+halfW);

    tt0 = tt-mean(tt);
    pp0 = pp-mean(pp);

    denom = sum(tt0.^2);

    if denom > 0
        slope = sum(tt0.*pp0)/denom;
        fInst(k) = slope/(2*pi);
    end
end

valid = isfinite(fInst);

if any(valid)
    smoothN = 3;
    temp = fInst;
    temp(valid) = movmean(fInst(valid),smoothN);
    fInst = temp;
end

end

%% =========================================================================
% VALIDATION
% =========================================================================
function textOut = validateFrequencyWaveform(fTheory,fActual,validMask)

valid = validMask & isfinite(fTheory) & isfinite(fActual);

if sum(valid) < 50
    textOut = 'CHECK | insufficient valid IF samples';
    return;
end

e = fActual(valid)-fTheory(valid);

rmsErr = sqrt(mean(e.^2));
maxErr = max(abs(e));

sweep = max(fTheory(valid))-min(fTheory(valid));
tolerance = max(10,0.01*abs(sweep));
normalizedRms = 100*rmsErr/max(abs(sweep),eps);

if rmsErr <= tolerance
    stateText = 'PASS';
else
    stateText = 'CHECK';
end

textOut = sprintf( ...
    '%s | core RMS %.4g Hz | core max %.4g Hz | %.4g%% of sweep', ...
    stateText,rmsErr,maxErr,normalizedRms);

end

function textOut = validatePhaseWaveform(wr,fTheory)

fc = numericOrNaN(wr.fc_kHz)*1e3;
carrierError = max(abs(fTheory-fc));

try
    [pr,~,fam] = extractPhaseData(wr);

    if isempty(pr)
        textOut = 'CHECK | phase data missing';
        return;
    end

    if carrierError <= 1e-9
        textOut = sprintf( ...
            'PASS | %s | %d chips | carrier %.6g kHz', ...
            char(fam),numel(pr),fc/1e3);
    else
        textOut = sprintf( ...
            'CHECK | carrier mismatch %.4g Hz',carrierError);
    end

catch ME
    textOut = ['CHECK | ' ME.message];
end

end

%% =========================================================================
% FFT
% =========================================================================
function [f,magDb] = waveformSpectrum(t,x)

N = numel(x);

if N < 16
    f=[]; magDb=[];
    return;
end

Fs = 1/mean(diff(t));

n = (0:N-1).';
w = 0.5*(1-cos(2*pi*n/max(1,N-1)));
xw = x(:).*w;

nfft = max(8192,2^nextpow2(N));
nfft = min(nfft,131072);

X = fft(xw,nfft);
X = X(1:floor(nfft/2)+1);

mag = abs(X);
mag = mag/max(mag+eps);

magDb = 20*log10(mag+eps);
f = (0:floor(nfft/2)).'*Fs/nfft;

end

%% =========================================================================
% PHASE DATA
% =========================================================================
function [phaseRad,bpsk,family] = extractPhaseData(wr)

family = toText(wr.phase_code_family);

bpsk = parseNumericList(toText(wr.phase_code_bpsk));
phaseRad = parseNumericList(toText(wr.phase_code_phase_rad));

if isempty(bpsk) && isempty(phaseRad)
    error('No phase data in waveform CSV.');
end

if isempty(phaseRad)
    if any(~ismember(bpsk,[-1 1]))
        error('BPSK values must be +1/-1.');
    end

    phaseRad = zeros(size(bpsk));
    phaseRad(bpsk<0)=pi;

elseif isempty(bpsk)
    bpsk = ones(size(phaseRad));
    bpsk(abs(wrapToPiLocal(phaseRad)-pi)<1e-9)=-1;
end

if numel(phaseRad) ~= numel(bpsk)
    error('BPSK and phase arrays have different lengths.');
end

declared = numericOrNaN(wr.phase_code_length);

if isfinite(declared) && declared > 0 && ...
        numel(phaseRad) ~= declared
    error('phase_code_length does not match phase array.');
end

end

%% =========================================================================
% ZOOM
% =========================================================================
function z = chooseZoom(type,wr,tpUs)

fc = numericOrNaN(wr.fc_kHz)*1e3;

if type == "Phase_Coded"
    try
        [pr,~,~] = extractPhaseData(wr);

        if ~isempty(pr)
            chipUs = numericOrNaN(wr.Tp_s)/numel(pr)*1e6;
            z = min(tpUs,max(1.6*chipUs,250));
        else
            z = min(tpUs,300);
        end
    catch
        z = min(tpUs,300);
    end
else
    carrierWindowUs = 45e6/max(fc,1);
    z = min(tpUs,max(300,carrierWindowUs));
end

end

%% =========================================================================
% UTILITIES
% =========================================================================
function fileName = pickCsvOrDefault(defaultName,titleText)

if exist(defaultName,'file') == 2
    fileName = defaultName;
    return;
end

[file,path] = uigetfile({'*.csv','CSV files (*.csv)'},titleText);

if isequal(file,0)
    error('CSV selection cancelled.');
end

fileName = fullfile(path,file);

end

function dataOut = normalizeUITableData(dataIn)

dataOut = dataIn;

for rr = 1:size(dataOut,1)
    for cc = 1:size(dataOut,2)
        v = dataOut{rr,cc};

        if isstring(v)
            if ismissing(v) || strlength(v)==0
                dataOut{rr,cc} = '';
            else
                dataOut{rr,cc} = char(v);
            end
        elseif ischar(v)
            % Already valid.
        elseif isnumeric(v) || islogical(v)
            % Already valid.
        else
            dataOut{rr,cc} = char(string(v));
        end
    end
end

end

function s = toText(v)

try
    s = string(v);

    if ismissing(s) || s=="<missing>"
        s="";
    end
catch
    s="";
end

end

function x = numericOrNaN(v)

if isnumeric(v)
    if isempty(v)
        x=NaN;
    else
        x=double(v(1));
    end
else
    x=str2double(string(v));
end

if isempty(x) || ~isfinite(x)
    x=NaN;
end

end

function v = parseNumericList(s)

s=toText(s);

if strlength(strtrim(s))==0 || ...
        lower(strtrim(s))=="nan" || ...
        lower(strtrim(s))=="<missing>"
    v=[];
    return;
end

s=strrep(s,';',',');
parts=split(strtrim(s),',');
parts=strtrim(parts);
v=str2double(parts);

if any(isnan(v))
    error('Invalid numeric list: %s',s);
end

v=v(:).';

end

function y=wrapToPiLocal(x)
y=mod(x+pi,2*pi)-pi;
end

function idx=displayIndices(N,maxPts)

if N<=maxPts
    idx=1:N;
else
    idx=round(linspace(1,N,maxPts));
end

end

function clearAxes(msg)

axList = findall(gcf,'Type','axes');

for k=1:numel(axList)
    axis(axList(k),'off');
    text(axList(k),0.05,0.85,msg, ...
        'Units','normalized', ...
        'FontWeight','bold', ...
        'Interpreter','none');
end

end

function assertRequiredColumns(tbl,requiredNames,sourceName)

available=tbl.Properties.VariableNames;
missing=requiredNames(~ismember(requiredNames,available));

if ~isempty(missing)
    error(['Required columns missing from %s:\n%s\n\n' ...
        'Available columns:\n%s'], ...
        sourceName, ...
        strjoin(missing,'\n'), ...
        strjoin(available,'\n'));
end

end

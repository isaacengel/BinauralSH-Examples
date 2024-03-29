% SH interpolation example. This script performs HRTF interpolation using
% three different methods:
%   1. MagLS (magnitude least squares)
%   2. TA (time-alignment)
%   3. BiMagLS: improved version of TA, which applies MagLS to reduce
%      magnitude errors
%
% For each method, we evaluate spatial orders ranging from 1 (lowest usable
% order) to 40 (very high order).
%
% The following plots are shown:
%   1. Interpolation errors (magnitude and phase) vs the target HRTF.
%   2. Interaural time differences (ITD) and level differences (ILD) and
%       their error vs the target HRTF.
%   3. Perceptual spectral difference (PSD) vs the target HRTF.
%   4. Performance per order according to various binaural models:
%       - Reijniers2014: localisation performance (lateral and polar)
%       - Baumgartner2020: externalisation rates
%       - Jelfs2011: speech reception in presence of maskers
%
% WARNING: this script can take several minutes to run and will generate a
% some large files.
%
% EXTERNAL DEPENDENCIES:
%   Auditory Modeling Toolbox (amtoolbox.sourceforge.net)
%
% AUTHOR: Isaac Engel - isaac.engel(at)imperial.ac.uk
% August 2021

%% Clear variables
clear

%% Flag to save figures as pdf
savefigs = 0; 

%% Ask user whether to run perceptual models (takes long)
res = input('Run longer analysis using perceptual models, which might take several minutes? (y/n): ','s');
if strcmpi(res,'y')
    runModels = 1;
elseif strcmpi(res,'n')
    runModels = 0;
else
    warning('Wrong input (it should be ''y'' or ''n''. Not running models...')
    runModels = 0;
end

%% Parameters
N_vec = [1,3,5,10:10:40]; % spatial orders to test
Nref = 44; % reference (very high) spatial order
r = 0.0875; % head radius = 8.75 cm
c = 343; % speed of sound
itdJND = 20; % ITD JND for plots, according to Klockgether 2016
ildJND = 0.6; % ILD JND for plots, according to Klockgether 2016

% HRTF file
hrirname = 'hrtfs/FABIAN_HRIR_measured_HATO_0.sofa';

% Working directory
workdir = 'processed_data'; % change as needed
[~,hrtfname] = fileparts(hrirname);
workdir = [workdir,'/',hrtfname];
if ~isfolder(workdir)
    fprintf('Making folder %s...\n',workdir)
    mkdir(workdir);
end
if ~isfolder([workdir,'/hnm'])
    fprintf('Making folder %s...\n',[workdir,'/hnm'])
    mkdir([workdir,'/hnm'])
end
if ~isfolder([workdir,'/results'])
    fprintf('Making folder %s...\n',[workdir,'/results'])
    mkdir([workdir,'/results'])
end

%% Load HRTF
SOFA_obj = SOFAload(hrirname); % load HRTF in SOFA format
[h,fs,az,el] = sofa2hrtf(SOFA_obj); % get HRTF data

% Zero-pad the HRIRs to increase frequency resolution
taps = 2048;
h = [h;zeros(taps-size(h,1),size(h,2),size(h,3))];

H = ffth(h); % to frequency domain
nfreqs = size(H,1);
f = linspace(0,fs/2,nfreqs).';

%% Get high-order Hnm
filename = sprintf('%s/hnm/ref.mat',workdir);
if isfile(filename) % load if it already exists
    fprintf('Found %s. Loading...\n',filename)
    load(filename,'hnm_ref','Hnm_TA_ref','Hnm_mag_ref')
else
    fprintf('Making reference hnm (also time-aligned Hnm, for Fig. 1)...\n');
    % Standard
    hnm_ref = toSH(h,Nref,'az',az,'el',el,'fs',fs,'mode','trunc');
    % Time-aligned
    hnm_TA_ref = toSH(h,Nref,'az',az,'el',el,'fs',fs,'mode','TA');
    Hnm_TA_ref = ffth(hnm_TA_ref);
    % Mag-only
    Y = AKsh(Nref,[],az*180/pi,el*180/pi,'real').';
    Hnm_mag_ref = mult3(abs(H),pinv(Y));
    % Save
    fprintf('Saving %s...\n',filename)
    save(filename,'hnm_ref','Hnm_TA_ref','Hnm_mag_ref','fs')
end
Hnm_ref = ffth(hnm_ref);

%% Defining test conditions
ncond = 3; 
% 1. MagLS
test_conditions{1}.name = 'MagLS';
test_conditions{1}.preproc = 'MagLS';
% 2. TA (time-aligned HRTF)
test_conditions{2}.name = 'TA';
test_conditions{2}.preproc = 'TA';
% 3. BiMagLS
test_conditions{3}.name = 'BiMagLS';
test_conditions{3}.preproc = 'BiMagLS';

%% Define a few direction subsets
% 1. Nearest neighbours to 110-point Lebedev grid
gridTestReq = sofia_lebedev(110,0);
[~,indLeb] = getGridSubset([az,el],gridTestReq,0);
indLeb = find(indLeb); % get indices
azLeb = az(indLeb);
elLeb = el(indLeb);
wLeb = gridTestReq(:,3);
% 2. Median plane (lat = 0 +/- 1 deg)
[lat,~]=sph2hor(az*180/pi,90-el*180/pi); % lat/pol coordinates
indMP = find(abs(lat)<1); 
azMP = az(indMP);
elMP = el(indMP);
% 3. Horizontal plane (el = 90 +/- 1 deg)
indHP = find(abs(el-pi/2)<(pi/180));
azHP = az(indHP);
% elHP = el(indHP);
indFront = find(abs(el-pi/2)<(pi/180) & abs(az)<(pi/180)); % front

%% Generate and save hnm for each test condition
fprintf('Generating hnms...\n')
for N=N_vec % iterate through spatial orders
    fprintf('Processing order %d...\n',N);
    for i=1:ncond
        name = test_conditions{i}.name;
        preproc = test_conditions{i}.preproc;
        filename = sprintf('%s/hnm/ord%0.2d_%s.mat',workdir,N,name);
        if isfile(filename)
            fprintf('\tFound %s. Skipping...\n',filename)
        else
            fprintf('\tGenerating hnm...\n');
            [hnm,~,varOut] = toSH(h,N,'az',az,'el',el,'fs',fs,'mode',preproc);
            fprintf('\tSaving %s...\n',filename)
            save(filename,'hnm','varOut')
        end  
    end
end

%% Interpolate HRTFs and generate results
fprintf('Generating results...\n')

%% First, run analysis for the reference (original HRTF)

missingModels = runModels;
saveFile = 1;
filename = sprintf('%s/results/ref.mat',workdir);

if isfile(filename)
    
    fprintf('\tFound %s. Loading...\n',filename)
    load(filename,'results')
    if isfield(results,'lat_acc') || ~runModels
        missingModels = 0;
        saveFile = 0;
    end
    
end

if ~isfile(filename) || missingModels
    
    fprintf('\tGenerating results for reference HRTF...\n')

    %% Numerical analysis
    % Magnitude and phase delay 110-point Lebedev grid
    results.mag = 20*log10(abs(H(:,indLeb,:)));
    results.pd = (-unwrap(angle(H(:,indLeb,1)))+unwrap(angle(H(:,indLeb,2))))./(2*pi*f)*1e6;
    % Loudness across directions
    [L,wERB,calibrationGain] = perceptualSpectrum(H,fs);
    Lavgd = sum(mult2(L,wERB),1); % ERB-weighted avg loudness per direction
    results.L = Lavgd;
    results.L_perDirection = L; % save to calculate PSD
    results.Lavg = sum(Lavgd(:,indLeb,:).*wLeb.',2); % weighted avg on the Lebedev grid
    results.calibrationGain = calibrationGain; % save to calibrate loudness
    % Interaural differences for horizontal plane
    results.itd = itdestimator(permute(h(:,indHP,:),[2,3,1]),'fs',fs,...
        'MaxIACCe','lp','upper_cutfreq', 3000,...
        'butterpoly', 10)*1e6;
    results.ild = getILD(h(:,indHP,:),fs);

    %% Reijniers 2014
    fprintf('\t\tRunning reijniers2014...\n'); tic
    % Make DTF and SOFA object for Lebedev grid directions only
    dtf = getDTF(h(:,indLeb,:),fs);
    SOFA_obj = hrtf2sofa(dtf,fs,azLeb,elLeb);
    % Preprocessing source information (demo_reijniers2014)
    [template_loc, target] = reijniers2014_featureextraction(SOFA_obj);
    % Run virtual experiments (demo_reijniers2014)
    num_exp = 100;
    [doa, params] = reijniers2014(template_loc, target, 'num_exp', num_exp);       
    % Calculate performance measures (demo_reijniers2014)
    results.lat_acc = reijniers2014_metrics(doa, 'accL'); % mean lateral error
    results.lat_prec = reijniers2014_metrics(doa, 'precL'); % lateral std
    results.pol_acc = reijniers2014_metrics(doa, 'accP'); % mean polar error
    results.pol_prec = reijniers2014_metrics(doa, 'precP'); % polar std
    results.template_loc = template_loc; % template DTF
    fprintf('\t\tFinished running reijniers2014 (took %0.2f s)...\n',toc);

    %% Run baumgartner2021
    fprintf('\t\tRunning baumgartner2021...\n'); tic
    % Make DTF for median plane directions only
    dtf = getDTF(h(:,indMP,:),fs);
    ndirs = numel(elMP);
    results.ext = nan(ndirs,1);
    template_ext = cell(ndirs,1);
    for j=1:ndirs
        template_ext{j} = hrtf2sofa(dtf(:,j,:),fs,azMP(j),elMP(j));
        % Get externalisation values
        results.ext(j) = baumgartner2021(template_ext{j},template_ext{j});
    end
    results.template_ext = template_ext; % template DTFs
    fprintf('\t\tFinished running baumgartner2021 (took %0.2f s)...\n',toc);

    %% Run jelfs2011
    fprintf('\t\tRunning jelfs2011...\n'); tic
    ndirs = numel(azHP);
    srm = nan(ndirs,1);
    target = squeeze(h(:,indFront,:)); % target fixed at front
    for j = 1:ndirs
        interferer = squeeze(h(:,indHP(j),:)); % interferer moves around the HP
        srm(j) = jelfs2011(target,interferer,fs);
    end 
    results.srm = srm;
    fprintf('\t\tFinished running jelfs2011 (took %0.2f s)...\n',toc);

    if saveFile
        %% Save results
        fprintf('\t\tSaving results in %s...\n',filename)
        save(filename,'results')
    end
    
end
    
mag_ref = results.mag; % to calculate magnitude error
pd_ref = results.pd; % to calculate phase delay error
Lref = results.L_perDirection; % to calculate PSD
Lavg_ref = results.Lavg; % to level-match loudness
calibrationGain = results.calibrationGain; % to calibrate perceptual spectrum
if runModels
    template_loc = results.template_loc; % template localisation model
    template_ext = results.template_ext; % template externalisation model
end
clear results

%% Then, for all test conditions
for N=N_vec % iterate through spatial orders
    fprintf('Processing order %d...\n',N);
    Y = [];
    for i=1:ncond % iterate through conditions
        missingModels = runModels;
        saveFile = 1;
        name = test_conditions{i}.name;
        filename = sprintf('%s/results/ord%0.2d_%s.mat',workdir,N,name);
        if isfile(filename)
            fprintf('\tFound %s. Loading...\n',filename)
            load(filename,'results')
            if isfield(results,'lat_acc') || ~runModels
                missingModels = 0;
                saveFile = 0;
            end
        end
        
        if ~isfile(filename) || missingModels
            fprintf('\tGenerating results...\n')

            if isempty(Y)
                Y = AKsh(N, [], az*180/pi, el*180/pi, 'real').';
            end

            %% Load hnm and interpolate to test grid
            hnm = load(sprintf('%s/hnm/ord%0.2d_%s.mat',workdir,N,name)).hnm;                
            isaligned = strcmp(name,'TA') || strcmp(name,'BiMagLS');
            hInterp = fromSH(hnm,fs,az,el,isaligned,r);
            HInterp = ffth(hInterp);

            %% Numerical analysis
            % Magnitude and phase delay error 110-point Lebedev grid
            mag = 20*log10(abs(HInterp(:,indLeb,:)));
            pd = (-unwrap(angle(HInterp(:,indLeb,1)))+unwrap(angle(HInterp(:,indLeb,2))))./(2*pi*f)*1e6;
            results.err_mag = mean(abs(mag-mag_ref),2); % avg abs difference across directions
            results.err_pd = mean(abs(pd-pd_ref),2); % avg abs difference across directions
            % Loudness across directions
            [L,wERB] = perceptualSpectrum(HInterp,fs,calibrationGain);
            Lavgd = sum(L.*wERB,1); % ERB-weighted avg loudness per direction
            Lavg = sum(Lavgd(:,indLeb,:).*wLeb.',2); % weighted avg on the Lebedev grid
            L = L - Lavg + Lavg_ref; % level-match with reference
            Lavgd = sum(L.*wERB,1); % recalculate avg loudness per direction
            Ldif = L-Lref; % loudness difference
            PSD = sum(abs(L-Lref).*wERB,1); % avg abs difference per direction (PSD)
            PSDavg = sum(PSD(:,indLeb,:).*wLeb.',2); % avg PSD over the Lebedev grid
            results.L = Lavgd;
            results.PSD = PSD;
            results.PSDavg = PSDavg;
            % Interaural differences for horizontal plane
            results.itd = itdestimator(permute(hInterp(:,indHP,:),[2,3,1]),'fs',fs,...
                'MaxIACCe','lp','upper_cutfreq', 3000,...
                'butterpoly', 10)*1e6;
            results.ild = getILD(hInterp(:,indHP,:),fs);
        end
        
        if missingModels
            %% Reijniers 2014
            fprintf('\t\tRunning reijniers2014...\n'); tic
            % Make DTF and SOFA object for Lebedev grid directions only
            dtf = getDTF(hInterp(:,indLeb,:),fs);
            SOFA_obj = hrtf2sofa(dtf,fs,azLeb,elLeb);
            % Preprocessing source information (demo_reijniers2014)
            [~, target] = reijniers2014_featureextraction(SOFA_obj);
            % Run virtual experiments (demo_reijniers2014)
            num_exp = 100;
            [doa, params] = reijniers2014(template_loc, target, 'num_exp', num_exp);       
            % Calculate performance measures (demo_reijniers2014)
            results.lat_acc = reijniers2014_metrics(doa, 'accL'); % mean lateral error
            results.lat_prec = reijniers2014_metrics(doa, 'precL'); % lateral std
            results.pol_acc = reijniers2014_metrics(doa, 'accP'); % mean polar error
            results.pol_prec = reijniers2014_metrics(doa, 'precP'); % polar std
            fprintf('\t\tFinished running reijniers2014 (took %0.2f s)...\n',toc);

            %% Run baumgartner2021
            fprintf('\t\tRunning baumgartner2021...\n'); tic
            % Make DTF for median plane directions only
            dtf = getDTF(hInterp(:,indMP,:),fs);
            ndirs = numel(elMP);
            results.ext = nan(ndirs,1);
            for j=1:ndirs
                target = hrtf2sofa(dtf(:,j,:),fs,azMP(j),elMP(j));
                % Get externalisation values
                results.ext(j) = baumgartner2021(target,template_ext{j});
            end
            fprintf('\t\tFinished running baumgartner2021 (took %0.2f s)...\n',toc);

            %% Run jelfs2011
            fprintf('\t\tRunning jelfs2011...\n'); tic
            ndirs = numel(azHP);
            srm = nan(ndirs,1);
            target = squeeze(hInterp(:,indFront,:)); % target fixed at front
            for j = 1:ndirs
                interferer = squeeze(hInterp(:,indHP(j),:)); % interferer moves around the HP
                srm(j) = jelfs2011(target,interferer,fs);
            end 
            results.srm = srm;
            fprintf('\t\tFinished running jelfs2011 (took %0.2f s)...\n',toc);
        end
        
        if saveFile
            %% Save results
            fprintf('\t\tSaving results in %s...\n',filename)
            save(filename,'results')
        end
    end
end

%% Fig. 1. Plot SH spectra
fig1size = [17.9324 3]; % 4.5212]; % [17.78 7];
fig1 = figure('units','centimeters','PaperUnits','centimeters',...
    'PaperSize',fig1size,'Renderer','painters',...
    'pos',[2 2 fig1size(1) fig1size(2)],...
    'paperposition',[0 0 fig1size(1) fig1size(2)]);
% Tight subplot
gap = [.02 .008]; % gap between subplots in norm units (height width)
marg_h = [.22 .03]; %[.18 .15]; % figure height margins in norm units (lower upper)
marg_w = [.05 .08]; % figure width margins in norm units (left right)
[ha, pos] = tight_subplot(1,3,gap,marg_h,marg_w);
% Fig. 1a: original HRTF
axes(ha(1)), plotSHenergy(Hnm_ref(:,:,1),fs); % left only
xlabel('f (Hz)'), ylabel('Order (N)')
axpos = get(ha(1),'pos');
annotation(fig1,'textbox',...
    [axpos(1)+axpos(3)-0.2 axpos(2)+axpos(4)-0.09 0.2 0.09],...
    'String',{'(a) Original'},...
    'HorizontalAlignment','right',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FitBoxToText','off',...
    'EdgeColor','none');
set(gca,'fontsize',7)
% Fig. 1b: time-aligned HRTF
axes(ha(2)), plotSHenergy(Hnm_TA_ref(:,:,1),fs);
xlabel('f (Hz)'), ylabel(''), yticklabels({})
axpos = get(ha(2),'pos');
annotation(fig1,'textbox',...
    [axpos(1)+axpos(3)-0.2 axpos(2)+axpos(4)-0.09 0.2 0.09],...
    'String',{'(b) Time-aligned'},...
    'HorizontalAlignment','right',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FitBoxToText','off',...
    'EdgeColor','none');
set(gca,'fontsize',7)
% Fig. 1c: magnitude-only HRTF
axes(ha(3)), plotSHenergy(Hnm_mag_ref(:,:,1),fs);
xlabel('f (Hz)'), ylabel('');
set(ha(3),'YTickLabel',{})
axpos = get(ha(3),'pos');
annotation(fig1,'textbox',...
    [axpos(1)+axpos(3)-0.2 axpos(2)+axpos(4)-0.09 0.2 0.09],...
    'String',{'(c) Magnitude only'},...
    'HorizontalAlignment','right',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FontName','Arial',...
    'FitBoxToText','off',...
    'EdgeColor','none');
set(gca,'fontsize',7,'FontName','Arial')
c = colorbar; c.Label.String = 'Energy (dB)';
c.Position = [0.9281 c.Position(2) c.Position(3) c.Position(4)]; % [0.9282    0.1784    0.0199    0.7934];

% annotation(fig1,'textbox',...
%     [0.165726631393298 0.641326487466018 0.121787429349109 0.192389006342492],...
%     'Color',[1 0 0],...
%     'String',{'Lowest order','containing','90% of','the energy'},...
%     'FontSize',7,...
%     'FontName','Arial',...
%     'FitBoxToText','off',...
%     'EdgeColor','none');
% annotation(fig1,'textbox',...
%     [0.0604944150499708 0.461942363837712 0.109162502835294 0.235729386892173],...
%     'Color',[0 0.749019607843137 0],...
%     'String',{'Lowest order','containing 99% of','the energy'},...
%     'FontSize',7,...
%     'FontName','Arial',...
%     'FitBoxToText','off',...
%     'EdgeColor','none');
% annotation(fig1,'arrow',[0.194003527336861 0.203997648442093],...
%     [0.643515705225008 0.476496677740864],'Color',[1 0 0]);
% annotation(fig1,'arrow',[0.0833627278071723 0.0880658436213992],...
%     [0.502481425551193 0.381974025974026],'Color',[0 0.749019607843137 0]);

% sgtitle('HRTF energy in the SH domain, before and after altering its phase')

if savefigs
    print(fig1,'plot_shspectra.pdf','-dpdf')
end

%% Fig. 2. Plot mag/phase errors per method, N=3
% Load data from file
names = {
    'ord03_MagLS'
    'ord03_TA'
    'ord03_BiMagLS'
};
labels = {
    'MagLS'
    'Bilateral'
    'BiMagLS'
};
n = numel(names);
err_mag = zeros(nfreqs,n);
err_pd = zeros(nfreqs,n);
for i=1:n
    name = names{i};
    filename = sprintf('%s/results/%s.mat',workdir,name);
    load(filename,'results');
    err_mag(:,i) = results.err_mag(:,1,1); % left ear only
    err_pd(:,i) = results.err_pd;
end

% Tight subplot
fig2size = [323.2 210];%250]; %[323.2000 319.6000];
fig2 = figure('pos',[56.6000 98.6000 fig2size(1) fig2size(2)]);
gap = [.04 .008]; % gap between subplots in norm units (height width)
marg_h = [.13 .02]; % [.09 .1] figure height margins in norm units (lower upper)
marg_w = [.1 .03]; % figure width margins in norm units (left right)
[ha, ~] = tight_subplot(2,1,gap,marg_h,marg_w);

% Top plot: magnitude error
colors = lines;
lsvec = {'-'};%,'-.'};
lwvec = [0.5,0.5];
mvec = {'o','s','d','x'};
ms = 3; % marker size
mi = int32(logspace(log10(1),log10(1025),10));
    
axes(ha(1))
for i=1:n
    ls = lsvec{mod(i-1,numel(lsvec))+1};
    lw = lwvec(mod(i-1,numel(lwvec))+1);
    m = mvec{i};
    semilogx(f,err_mag(:,i),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi); hold on
end

fa = 3*343/(2*pi*r);
semilogx([fa fa],[0 6],'k--')
semilogx([f(2) 20000], [1 1],'k:')
legend(labels,'location','west')

ylim([0 6])
xlabel(''), xticklabels({}), xlim([f(2) 20000])
ylabel('Error (dB)'), grid on
axpos = get(ha(1),'pos');
annotation(fig2,'textbox',...
    [axpos(1) axpos(2)+axpos(4)-0.09 0.5 0.09],...
    'String',{' Magnitude error'},...
    'HorizontalAlignment','left',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FitBoxToText','off',...
    'EdgeColor','none');

% Bottom plot: phase error
axes(ha(2))
for i=1:n
    ls = lsvec{mod(i-1,numel(lsvec))+1};
    lw = lwvec(mod(i-1,numel(lwvec))+1);
    m = mvec{i};
    semilogx(f,err_pd(:,i),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi); hold on
end

semilogx([fa fa],[0 300],'k--')
semilogx([f(2) 20000], [20 20],'k:')
ylim([0 300])
xlim([f(2) 20000]), grid on, ylabel('Error (\mus)')
xticks([100,1000,10000,20000])
xticklabels({'100','1k','10k','20k'})    
xlabel('f (Hz)')
axpos = get(ha(2),'pos');
annotation(fig2,'textbox',...
    [axpos(1) axpos(2)+axpos(4)-0.09 0.5 0.09],...
    'String',{' Phase delay error'},...
    'HorizontalAlignment','left',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FitBoxToText','off',...
    'EdgeColor','none');

set(ha,'fontsize',7)
set(gcf,'units','centimeters','Renderer','painters')
figpos = get(gcf,'position');
set(gcf,'PaperSize',[figpos(3) figpos(4)],'paperposition',[0 0 figpos(3) figpos(4)])
% sgtitle('Interpolation errors (non-aligned HRTF)')

if savefigs
    print(fig2,'plot_interrors.pdf','-dpdf')
end

%% Fig. 3. Plot ITD/ILD per method, N=3
% Load data from file
names = {
    'ord03_MagLS'
    'ord03_TA'
    'ord03_BiMagLS'
    'ref'
};
labels = {
    'MagLS'
    'Bilateral'
    'BiMagLS'
    'Reference'
};
n = numel(names);
ndirs = numel(azHP);
itd = zeros(ndirs,n);
ild = zeros(ndirs,n);
for i=1:n
    name = names{i};
    filename = sprintf('%s/results/%s.mat',workdir,name);
    load(filename,'results');
    itd(:,i) = results.itd;
    ild(:,i) = results.ild;
end

% Tight subplot  
fig3size = [17.9112 7.5]; % [17.9112 9];
fig3 = figure('units','centimeters','pos',[2 2 fig3size(1) fig3size(2)],...
    'Renderer','painters','PaperSize',[fig3size(1) fig3size(2)],...
    'paperposition',[0 0 fig3size(1) fig3size(2)]);

ha(1) = polaraxes('Position',[0.05 0.3 0.39 0.61]);
ha(2) = polaraxes('Position',[0.56 0.3 0.39 0.61]);

%more figs
fig3asize = [8 6]; % 8
fig3a = figure('units','centimeters','pos',[2 2 fig3asize(1) fig3asize(2)],...
    'Renderer','painters','PaperSize',[fig3asize(1) fig3asize(2)],...
    'paperposition',[0 0 fig3asize(1) fig3asize(2)]);
ha(5) = polaraxes('Position',[0.05 0.3 0.9 0.58]); % 0.61]);
fig3b = figure('units','centimeters','pos',[2 2 fig3asize(1) fig3asize(2)],...
    'Renderer','painters','PaperSize',[fig3asize(1) fig3asize(2)],...
    'paperposition',[0 0 fig3asize(1) fig3asize(2)]);
ha(6) = polaraxes('Position',[0.05 0.3 0.9 0.58]);% 0.61]);
 
colors = lines;
lsvec = {'-'};%,'-.'};
lwvec = [0.5,0.5];
mvec = {'o','s','d','x'};
ms = 3; % marker size
step_big = round(numel(azHP)/4);
step_small = round(step_big/n);
    
% ITD
axes(ha(1))
for i=1:n % multiply by 0.001 to have it in ms (cleaner plot)
    ls = lsvec{mod(i-1,numel(lsvec))+1};
    lw = lwvec(mod(i-1,numel(lwvec))+1);
    m = mvec{i};
    mi = [((i-1)*step_small+1):step_big:numel(azHP)-1]; % marker indices
    color = colors(i,:);
    if i==n % reference
        ls = ':';
        lw = 0.5;
        m = 'none';
        color = [0 0 0];
    end
    axes(ha(1))
    polarplot(azHP,abs(itd(:,i))*0.001,'Color',color,'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi), hold on
    axes(ha(5))
    polarplot(azHP,abs(itd(:,i))*0.001,'Color',color,'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi), hold on
end
axes(ha(1))
set(gca,'ThetaZeroLocation','top','ThetaLim',[0 360])
set(gca,'ThetaTick',[0:45:360],'ThetaTickLabel',{'0','45','90','135','','-135','-90','-45'},'RAxisLocation',-90)
title('ITD (ms)')
set(gca,'fontsize',7)
axes(ha(5))
set(gca,'ThetaZeroLocation','top','ThetaLim',[0 360])
set(gca,'ThetaTick',[0:45:360],'ThetaTickLabel',{'0','45','90','135','','-135','-90','-45'},'RAxisLocation',-90)
legend(labels,'position',[0.6524    0.0647    0.2983    0.1883]);%[0.4432  0.6219  0.1135  0.1883]);
title('ITD (ms)')
set(gca,'fontsize',7)

% ILD
axes(ha(2))
for i=1:n
    ls = lsvec{mod(i-1,numel(lsvec))+1};
    lw = lwvec(mod(i-1,numel(lwvec))+1);
    m = mvec{i};
    mi = [((i-1)*step_small+1):step_big:numel(azHP)-1]; % marker indices
    color = colors(i,:);
    if i==n % reference
        ls = ':';
        lw = 0.5;
        m = 'none';
        color = [0 0 0];
    end
    axes(ha(2))
    polarplot(azHP,abs(ild(:,i)),'Color',color,'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi), hold on
    axes(ha(6))
    polarplot(azHP,abs(ild(:,i)),'Color',color,'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi), hold on
end
axes(ha(2))
set(gca,'ThetaZeroLocation','top','ThetaLim',[0 360])
set(gca,'ThetaTick',[0:45:360],'ThetaTickLabel',{'0','45','90','135','','-135','-90','-45'},'RAxisLocation',-90)
title('ILD (dB)')
legend(labels,'position',[0.4432  0.75  0.1135  0.1883]);%[0.4432  0.6219  0.1135  0.1883]);
set(gca,'fontsize',7)
axes(ha(6))
set(gca,'ThetaZeroLocation','top','ThetaLim',[0 360])
set(gca,'ThetaTick',[0:45:360],'ThetaTickLabel',{'0','45','90','135','','-135','-90','-45'},'RAxisLocation',-90)
title('ILD (dB)')
legend(labels,'position',[0.6524    0.0647    0.2983    0.1883]);%[0.4432  0.6219  0.1135  0.1883]);
set(gca,'fontsize',7)

itderr = abs(itd-itd(:,end));
ilderr = abs(ild-ild(:,end));

ha(3) = axes(fig3,'Position',[0.05 0.05 0.39 0.23]);
axes(ha(3))
violinplot(itderr(:,1:end-1),[],'ShowData',false,'BoxWidth',0.03,'Colors',colors); grid on
set(gca,'YTickLabelMode','auto')
hold on, plot([0 n],[itdJND itdJND],'k:')
xticklabels(labels(1:end-1))
ylabel('Abs. ITD error (ms)')
set(gca,'fontsize',6)
ylim([0 600])

ha(4) = axes(fig3,'Position',[0.56 0.05 0.39 0.23]);
axes(ha(4))
violinplot(ilderr(:,1:end-1),[],'ShowData',false,'BoxWidth',0.03,'Colors',colors); grid on
set(gca,'YTickLabelMode','auto')
hold on, plot([0 n],[ildJND ildJND],'k:')
xticklabels(labels(1:end-1))
ylabel('Abs. ILD error (dB)')
set(gca,'fontsize',6)
ylim([0 6])

ha(7) = axes(fig3a,'Position',[0.1 0.07 0.5 0.21]); %[0.1 0.05 0.5 0.23]
axes(ha(7))
violinplot(itderr(:,1:end-1),[],'ShowData',false,'BoxWidth',0.03,'Colors',colors); grid on
set(gca,'YTickLabelMode','auto')
hold on, plot([0 n],[itdJND itdJND],'k:')
xticklabels(labels(1:end-1))
ylabel('Abs. ITD error (ms)')
set(gca,'fontsize',6)
ylim([0 600])

ha(8) = axes(fig3b,'Position',[0.1 0.07 0.5 0.21]); %[0.1 0.05 0.5 0.23]
axes(ha(8))
violinplot(ilderr(:,1:end-1),[],'ShowData',false,'BoxWidth',0.03,'Colors',colors); grid on
set(gca,'YTickLabelMode','auto')
hold on, plot([0 n],[ildJND ildJND],'k:')
xticklabels(labels(1:end-1))
ylabel('Abs. ILD error (dB)')
set(gca,'fontsize',6)
ylim([0 6])

if savefigs
    print(fig3,'plot_itdild.pdf','-dpdf')
    print(fig3a,'plot_itd.pdf','-dpdf')
    print(fig3b,'plot_ild.pdf','-dpdf')
end

%% Fig. 4. Plot PSD per direction, N=3
% Load data from file
names = {
    'ord03_MagLS'
    'ord03_TA'
    'ord03_BiMagLS'
};
labels = {
    'MagLS'
    'Bilateral'
    'BiMagLS'
};
n = numel(names);
ndirs = numel(az);
L = cell(n,1);
PSD = zeros(ndirs,n);
PSDavg = zeros(n,1);
for i=1:n
    name = names{i};
    filename = sprintf('%s/results/%s.mat',workdir,name);
    load(filename,'results');
    L{i} = results.L;
    if isfield(results,'PSD')
        PSD(:,i) = results.PSD(:,:,1).'; % left ear only
        PSDavg(i) = results.PSDavg(:,:,1); % left ear only
    end
end

% Tight subplot
fig4size = [16.4253 8];
fig4 = figure('units','centimeters','pos',[2 2 fig4size(1) fig4size(2)],...
    'Renderer','painters','PaperSize',[fig4size(1) fig4size(2)],...
    'paperposition',[0 0 fig4size(1) fig4size(2)]);
gap = [.07 .008]; % gap between subplots in norm units (height width)
marg_h = [.5 .05]; % [.5 .15] figure height margins in norm units (lower upper)
marg_w = [.06 .1]; % figure width margins in norm units (left right)
[ha, ~] = tight_subplot(1,3,gap,marg_h,marg_w);
clims = [0 0.65]; % change as needed

colormap parula
for i=1:n
    axes(ha(i)) 
    plotSph(az,el,PSD(:,i))
    if i==1
        set(ha(i),'YTick',-60:30:60)
        ylabel('Elevation (deg)')
    else
       set(ha(i),'YTickLabel',{})
    end
    xlabel('Azimuth (deg)')
    title(labels{i})

    set(gca,'fontsize',7,'XDir','reverse')
    grid(gca,'off')
    caxis(clims)
    if i==n
        c = colorbar; c.Label.String = 'Loudness (sones)';
        c.Position = [0.909 c.Position(2) c.Position(3) c.Position(4)];
    end
end 

ax = axes('innerposition',[0.4 0.05 0.3 0.3]);
violinplot(PSD(indLeb,1:end),[],'ShowData',false,'BoxWidth',0.03,'Colors',colors); grid on
xticklabels(labels(1:end))
ylabel('PSD (sones)')
set(gca,'fontsize',7)

if savefigs
    print(fig4,'plot_psd.pdf','-dpdf')
end

%% Fig. 5. Plots models' outputs per spatial order

if runModels
    
% Load data from file
names = {
    'MagLS'
    'TA'
    'BiMagLS'
    'ref'
};
labels = {
    'MagLS'
    'Bilateral'
    'BiMagLS'
    'Reference'
};
n = numel(names);
m = numel(N_vec);
PSD = nan(n,m);
lat_prec = nan(n,m);
pol_prec = nan(n,m);
ext = nan(n,m);
srm = nan(n,m);
for i=1:n
    name = names{i};
    if strcmp(name,'ref')
        filename = sprintf('%s/results/ref.mat',workdir);
        load(filename,'results');
        PSD(i,:) = 0;
        lat_prec(i,:) = results.lat_prec;
        pol_prec(i,:) = results.pol_prec;
        ext(i,:) = mean(results.ext); 
        srm(i,:) = mean(results.srm);
    else
        for j=1:m
            N=N_vec(j);
            filename = sprintf('%s/results/ord%0.2d_%s.mat',workdir,N,name);
            load(filename,'results');
            PSD(i,j) = results.PSDavg(:,:,1); % left ear only
            lat_prec(i,j) = results.lat_prec;
            pol_prec(i,j) = results.pol_prec;
            ext(i,j) = mean(results.ext); 
            srm(i,j) = mean(results.srm);
        end
    end
end
% Tight subplot
fig5size = [18.3938 9.7790];
fig5 = figure('units','centimeters','pos',[2 2 fig5size(1) fig5size(2)],...
    'Renderer','painters','PaperSize',[fig5size(1) fig5size(2)],...
    'paperposition',[0 0 fig5size(1) fig5size(2)]);
gap = [.06 .05]; % gap between subplots in norm units (height width)
marg_h = [.1 .1]; % [.09 .1] figure height margins in norm units (lower upper)
marg_w = [.07 .02]; % figure width margins in norm units (left right)
[ha, ~] = tight_subplot(2,3,gap,marg_h,marg_w); 
    
colors = lines;
lsvec = {'-'};%,'-.'};
mvec = {'o','s','d','x'};
lwvec = [0.5,0.5];
ms = 3; % marker size
mi = 1:n; % [1:5:44]; % marker indices
    
colors(end,:) = [0 0 0]; % last one is reference
  
for i=1:n
    if i<n
        ls = lsvec{mod(i-1,numel(lsvec))+1};
        lw = lwvec(mod(i-1,numel(lwvec))+1);
        m = mvec{i};
    else
        ls = ':'; % reference
        lw = 0.5;
        m = 'None';
    end
    plot(ha(1),N_vec,PSD(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(1),'on')
    plot(ha(2),N_vec,lat_prec(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(2),'on')
    plot(ha(3),N_vec,pol_prec(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(3),'on')
    plot(ha(4),N_vec,ext(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(4),'on')
    plot(ha(5),N_vec,srm(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(5),'on')
end
legh = legend(ha(1),labels,'location','best');

ylabel(ha(1),'PSD (sones)')%, ylim(ha(1),[min(PSD(:),max(PSD(:)])
ylabel(ha(2),'Lateral precision (deg)')
ylabel(ha(3),'Polar precision (deg)')
ylabel(ha(4),'Externalisation')%, ylim(ha(4),[0.3 1.01])
ylabel(ha(5),'SRM (dB)') % , ylim(ha(4),[0.3 1.01])
for i=1:5
    grid(ha(i),'on')
    xlim(ha(i),[1 44])
    xticks(ha(i),[1,5:5:44])
    if i<=3
%             xticklabels(ha(i),{})
    else
        xlabel(ha(i),'Spatial order (N)')
    end
    set(ha(i),'fontsize',7)
end
set(ha(6),'visible','off')

sgtitle('Perceptual models'' output (per order)')

if savefigs
    print(fig5,'plot_models.pdf','-dpdf')
end

end

%% Fig. 5b. Plots (fewer) models' outputs per spatial order

if runModels
    
% Load data from file
names = {
    'MagLS'
    'TA'
    'BiMagLS'
    'ref'
};
labels = {
    'MagLS'
    'Bilateral'
    'BiMagLS'
    'Reference'
};
n = numel(names);
m = numel(N_vec);
PSD = nan(n,m);
lat_prec = nan(n,m);
pol_prec = nan(n,m);
for i=1:n
    name = names{i};
    if strcmp(name,'ref')
        filename = sprintf('%s/results/ref.mat',workdir);
        load(filename,'results');
        PSD(i,:) = 0;
        lat_prec(i,:) = results.lat_prec;
        pol_prec(i,:) = results.pol_prec;
    else
        for j=1:m
            N=N_vec(j);
%             filename = sprintf('%s/results/ord%0.2d_%s.mat',workdir,N,name);
            filename = sprintf('C:/Users/Isaac/Box Sync/github/amtoolbox-code/cache/experiments%%2Fexp_engel2021.m/res_ord%0.2d_%s.mat',N,name);
%             load(filename,'results');
            s = load(filename);
            results = s.cache.value;
            PSD(i,j) = results.PSDavg(:,:,1); % left ear only
            lat_prec(i,j) = results.lat_prec;
            pol_prec(i,j) = results.pol_prec;
        end
    end
end
% Tight subplot
fig5bsize = [8 7.5]; % [16.4253 5];
fig5b = figure('units','centimeters','pos',[2 2 fig5bsize(1) fig5bsize(2)],...
    'Renderer','painters','PaperSize',[fig5bsize(1) fig5bsize(2)],...
    'paperposition',[0 0 fig5bsize(1) fig5bsize(2)]);
gap = [.04 .05]; % gap between subplots in norm units (height width)
marg_h = [.1 .02]; % [.09 .1] figure height margins in norm units (lower upper)
marg_w = [.1 .02]; % figure width margins in norm units (left right)
[ha, ~] = tight_subplot(3,1,gap,marg_h,marg_w); 
    
colors = lines;
lsvec = {'-'};%,'-.'};
mvec = {'o','s','d','x'};
lwvec = [0.5,0.5];
ms = 3; % marker size
mi = [1:5:44]; % marker indices
    
colors(end,:) = [0 0 0]; % last one is reference
  
for i=1:n
    if i<n
        ls = lsvec{mod(i-1,numel(lsvec))+1};
        lw = lwvec(mod(i-1,numel(lwvec))+1);
        m = mvec{i};
    else
        ls = ':'; % reference
        lw = 0.5;
        m = 'None';
    end
    plot(ha(1),N_vec,PSD(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(1),'on')
    plot(ha(2),N_vec,lat_prec(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(2),'on')
    plot(ha(3),N_vec,pol_prec(i,:),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi),hold(ha(3),'on')
end
legh = legend(ha(1),labels,'location','ne');

ylabel(ha(1),'PSD (sones)')%, ylim(ha(1),[min(PSD(:),max(PSD(:)])
ylabel(ha(2),'Lat. precision (º)')
ylabel(ha(3),'Pol. precision (º)')
for i=1:3
    grid(ha(i),'on')
    xlim(ha(i),[1 44])
    if i==3
        xticks(ha(i),[1,5:5:44])
        xlabel(ha(i),'Spatial order (N)')
    else
        xlabel(ha(i),'')
        xticklabels(ha(i),{})
    end
    set(ha(i),'fontsize',7)
end

% sgtitle('Perceptual models'' output (per order)')

if savefigs
    print(fig5b,'plot_fewmodels.pdf','-dpdf')
end

end

%% Other figures
fig6size = [8 3];
fig6 = figure('units','centimeters','pos',[2 2 fig6size(1) fig6size(2)],...
    'Renderer','painters','PaperSize',[fig6size(1) fig6size(2)],...
    'paperposition',[0 0 fig6size(1) fig6size(2)]);
nvec = 1:44;
fc = nvec*343/(2*pi*0.0875);
fc2 = max(fc,3000);
plot(nvec,[fc;fc2]/1000)
grid on
legend({'MagLS','BiMagLS'},'location','nw')
xlabel('Spatial order (N)'), ylabel('Cutoff (kHz)')
xlim([1,44]),ylim([0,max(fc/1000)]), xticks([0:5:44])
set(gca,'fontsize',7)
if savefigs
    print(fig6,'plot_fc.pdf','-dpdf')
end

%% Other figures: smoothing
kvec = [0,0.5,1,2];
labels = {'k = 0','k = 0.5','k = 1','k = 2'};
hnm_k{1} = toSH(h,3,'az',az,'el',el,'fs',fs,'mode','MagLS','k',kvec(1));
hnm_k{2} = toSH(h,3,'az',az,'el',el,'fs',fs,'mode','MagLS','k',kvec(2));
hnm_k{3} = toSH(h,3,'az',az,'el',el,'fs',fs,'mode','MagLS','k',kvec(3));
hnm_k{4} = toSH(h,3,'az',az,'el',el,'fs',fs,'mode','MagLS','k',kvec(4));
for i=1:4
    h_k{i} = fromSH(hnm_k{i},fs,az,el,false,r);
    H_k{i} = ffth(h_k{i});
    mag = 20*log10(abs(H_k{i}(:,indLeb,:)));
    pd = (-unwrap(angle(H_k{i}(:,indLeb,1)))+unwrap(angle(H_k{i}(:,indLeb,2))))./(2*pi*f)*1e6;
    err_mag_k{i} = mean(abs(mag-mag_ref),2); % avg abs difference across directions
    err_pd_k{i} = mean(abs(pd-pd_ref),2); % avg abs difference across directions
end

% Tight subplot [
fig7 = figure('pos',[56.6000 98.6000 323.2 210]);%250]); %[323.2000 319.6000];]);
gap = [.04 .008]; % gap between subplots in norm units (height width)
marg_h = [.13 .01]; % [.09 .1] figure height margins in norm units (lower upper)
marg_w = [.1 .03]; % figure width margins in norm units (left right)
[ha, ~] = tight_subplot(2,1,gap,marg_h,marg_w);

% Top plot: magnitude error
colors = parula(5);
lsvec = {'-'};%,'-.'};
lwvec = [0.5,0.5];
mvec = {'o','s','d','x'};
ms = 3; % marker size
mi = int32(logspace(log10(1),log10(1025),10));
    
axes(ha(1))
for i=1:4
    ls = lsvec{mod(i-1,numel(lsvec))+1};
    lw = lwvec(mod(i-1,numel(lwvec))+1);
    m = mvec{i};
    semilogx(f,err_mag_k{i}(:,:,1),'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi); hold on
end

fa_k = 3*343/(2*pi*r);
semilogx([fa_k fa_k],[0 4.6],'k--')
semilogx([f(2) 20000], [1 1],'k:')
legend(labels,'location','west')

ylim([0 4.6])
xlabel(''), xticklabels({}), xlim([f(2) 20000])
ylabel('Error (dB)'), grid on
axpos = get(ha(1),'pos');
annotation(fig7,'textbox',...
    [axpos(1) axpos(2)+axpos(4)-0.09 0.5 0.09],...
    'String',{' Magnitude error'},...
    'HorizontalAlignment','left',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FitBoxToText','off',...
    'EdgeColor','none');

% Bottom plot: phase error
axes(ha(2))
for i=1:4
    ls = lsvec{mod(i-1,numel(lsvec))+1};
    lw = lwvec(mod(i-1,numel(lwvec))+1);
    m = mvec{i};
    semilogx(f,err_pd_k{i},'Color',colors(i,:),'LineWidth',lw,'LineStyle',ls,'Marker',m,'MarkerSize',ms,'MarkerIndices',mi); hold on
end

semilogx([fa_k fa_k],[0 300],'k--')
semilogx([f(2) 20000], [20 20],'k:')
ylim([0 300])
xlim([f(2) 20000]), grid on, ylabel('Error (\mus)')
xticks([100,1000,10000,20000])
xticklabels({'100','1k','10k','20k'})    
xlabel('f (Hz)')
axpos = get(ha(2),'pos');
annotation(fig7,'textbox',...
    [axpos(1) axpos(2)+axpos(4)-0.09 0.5 0.09],...
    'String',{' Phase delay error'},...
    'HorizontalAlignment','left',...
    'FontWeight','bold',...
    'FontSize',7,...
    'FitBoxToText','off',...
    'EdgeColor','none');

set(ha,'fontsize',7)
set(gcf,'units','centimeters','Renderer','painters')
figpos = get(gcf,'position');
set(gcf,'PaperSize',[figpos(3) figpos(4)],'paperposition',[0 0 figpos(3) figpos(4)])
% sgtitle('Interpolation errors (non-aligned HRTF)')

if savefigs
    print(fig7,'plot_interrors_smoothing.pdf','-dpdf')
end
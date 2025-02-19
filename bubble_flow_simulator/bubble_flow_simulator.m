%% Copyrights
%%% Author: Hatim Belgharbi

%% Featured publications

% Milecki L, Poree J, Belgharbi H, et al. 
% A Deep Learning Framework for Spatiotemporal Ultrasound Localization 
% Microscopy. IEEE Trans Med Imaging. 2021;40(5):1428-1437. 
% doi.org/10.1109/TMI.2021.3056951

% Hardy E, Por�e J, Belgharbi H, Bourquin C, Lesage F, Provost J. 
% Sparse channel sampling for ultrasound localization microscopy 
% (SPARSE-ULM). Phys Med Biol. 2021;66(9):10.1088/1361-6560/abf1b6. 
% Published 2021 Apr 23. doi.org/10.1088/1361-6560/abf1b6

% Belgharbi H, Por�e J, Damseh R, Perrot V, Delafontaine-Martel P,
% Lesage F, Provost J.
% An Anatomically and Hemodynamically Realistic Simulation Framework 
% for 3D Ultrasound Localization Microscopy. Biorxiv. 2021. 
% doi.org/10.1101/2021.10.08.463259

%% Introduction
%%% Welcome. This is a 3D microbubble simulation (MB) framework based on 
%%% two-photon microscopy (2PM) and in-vivo MB perfusion dynamics.
%%%
%%% The simulation takes place in 3 main steps.
%%% 1) Pre-processing of data before simulation
%%% 2) Simulation of MB trajectories
%%% 3) Distributung MB in a steady state flow (SSF)

%%% 1. The first step consists of defining parameters necessary for the
%%% simulation, such as the framerate, filename, source nodes, target nodes,
%%% etc., but also calculating different arrays in advance, such as the 
%%% velocity-to-diameter dependancy, number of MB to diameter dependancy, 
%%% etc. Some of them can be modified to suit your specific needs.


%%% 2. In the 2nd step, we want to generate complete trajectories of MB. 
%%% These trajectories are defined using the parameters from step 1.

%%% 3. In the second step, we want to use those simulated MB positions from
%%% the 2nd section to populate the network using a constant set of MB. In
%%% other words, at each timeframe, we will have the positions of a 
%%% constant set of MB, in X, Y and Z.

clear all
close all
clc

%% 0.1 Visualization
%%% Choose wheather you would like:
%%% display = 0; No display
%%% display = 1; Minimal display
%%% display = 2; All display

display = 1; 

%% 0.2 Essential Variables
%%% Modify these variables according to your specifications. You must plan
%%% the number of total MB (n_bubbles) to be sufficient to populate your
%%% steady-state flow (SSF). The larger the number of MB in the SSF,
%%% the larger the number of total MB required. Same goes for the SSF duration 
%%% (n_bubbles_steady_state). A longer SSF would require more simulated MB
%%% trajectories to populate the SSF for a longer period of time.

%%% The pulsatility parameter enables you to choose to apply a pulsatile
%%% flow to your MB trajectories. Section 1.8 details some parameters used
%%% to replicate a pulsatile flow.

%%% The bypass_N_vs_d_stats parameter enables a simulation where the number
%%% of MB per diameter constraint is disabled. This allows the simulation
%%% of all possible trajectories. You would choose this option if you are
%%% less concerned with a realistic MB distribution and more concerned in
%%% filling more of the smaller vessels for demonstration purposes.

name = 'tree5';     % Name of the .swc graph model
file_name = 'test'; % Name of the dataset
samp_freq = 1000;   % Sampling frequency of the MB trajectories (Hz)
n_bubbles = 10000;   % Number of MB trajectories generated
bb_per_paquet = n_bubbles/100;  % n_trajectories per paquet (for storage)
n_bubbles_steady_state = 3000;   % Number of MB in the steady-state (SS) simulation
t_steady_state = 1;   % Desired simulation time (s)
bubble_size = 2;        % MB diameter (um)

pulsatility = 1;        % 1 = Yes | 0 = No

bypass_N_vs_d_stats = 1; % 0: Realistic, 1: Non-realistic

%% 0.3 Path and Folders Management
%%% Generating paths to folders of the simulator. Also creates a folder for
%%% saving in the parent folder of the root of the simulator to avoid
%%% saving directly in the git-managed folder.
disp('Running...')
addpath(genpath('..\..\hatimb-particle_flow_simulator\'));
root = dir('..\..\');
root_dir = root(1).folder;
save_dir = '\hatimb-particle_flow_simulator_DATA'; % Data is stored outide the Github folder
mkdir(root_dir,save_dir);
save_path = [root_dir save_dir '\'];

%%% Since we divide the simulation in paquets to reduce RAM utilization
%%% during simulation, a directory is created to contain temporary paquets
%%% of microbubble (MB) trajectories.

mkdir(root_dir,[save_dir '\temp']);

%% 1.1 Loading and processing the graph model
%%% The "tree5.swc" dataset is extracted from data presented in the 
%%% following article and used here with permission of the owner:
%%% R. Damseh et al., "Automatic Graph-Based Modeling of Brain 
%%% Microvessels Captured With Two-Photon Microscopy," in IEEE Journal 
%%% of Biomedical and Health Informatics, vol. 23, no. 6, pp. 2551-2562, 
%%% Nov. 2019, doi: 10.1109/JBHI.2018.2884678.
%%% You can generate this type of file (.swc) using the app designed by
%%% Rafat Damseh in his Github directory:
%%% https://github.com/Damseh/VascularGraph
%%% to convert a binary vascular volume into a graph model. To obtain an
%%% .swc tree file, you must convert the directed graph into a tree graph
%%% and save it.

filename = [name '.swc'];
g = importdata(filename);

target = g(:,1);    % Nodes IDs
source = g(:,7);    % Parent node
pos = g(:,3:5);     % Positions [x,y,z]
r = g(:,6);         % Nodes radii
r_norm = r./max(r); % Normalized radii [0,1]
r_inverse = 1./r;   % Calculating the inverse
r_inverse_norm = 1./r_norm; % Normalized inverse radii [0,1]

if display == 2
    %%% Display a histogram of the original nodes radii
    figure(1);clf
    hist(r);xlabel('radius');ylabel('N');
    [counts,centers] = hist(r);
end

if or(display == 1, display == 2)
    %%% Display network nodes
    figure(2);clf
    h = scatter3(pos(:,1),pos(:,2),pos(:,3),1,[1 1 1]); % Shortest path nodes);
    alpha = 0.2;
    set(h, 'MarkerEdgeAlpha', alpha, 'MarkerFaceAlpha', alpha)
    darkBackground(gcf)   
    axis equal;
    xlabel('x (\mum)')
    ylabel('y (\mum)')
    zlabel('z (\mum)')
    title('Graph Network');
end
drawnow

%% 1.2 Positions scaling
%%% If the dataset has anisotropic voxel, i.e. the dimension of each voxel
%%% is not the same or is not in um, use this section to strech or compress
%%% positions to their real dimention.

% dim_1 = 2;    % Dimension of the voxel in x(um)
% dim_2 = 2;    % Dimension of the voxel in y(um)
% dim_3 = 50;   % Dimension of the voxel in z(um)
% pos(:,1) = pos(:,1) * dim_1;
% pos(:,2) = pos(:,2) * dim_2;
% pos(:,3) = pos(:,3) * dim_3;
% r = r .* (dim_1+dim_2)/2;

%% 1.3 Source, target, end and bifurcation nodes
%%% Using source nodes from the file, we modify them to be used in MATLAB
%%% with coefficients starting with 1
s = source+2;   % Source nodes
t = target+2;   % Target nodes
%%% We find end-nodes by looking at nodes that don't have parent nodes.
C = setxor(s,1:length(s)); % Finding missing parents
end_nodes = [C-1;s(end)];  % Adding last extremity
clear C

%%% Finding bifurcations
%%% To find bifurcation nodes, we look at nodes that have 2 successor
%%% nodes, which makes them biffurcation nodes.
[uniqueA, i, j] = unique(s,'first');        % Finding unique nodes
tmp = find(not(ismember(1:numel(s),i)));    % idx of duplicates
tmp2 = s(tmp);                              % duplicates
[biff_nodes, ~, ~] = unique(tmp2,'first');% Keeping only first occurence
biff_nodes = biff_nodes-1; % it is the previous node

if display == 2
    figure(3);clf
    %scatter3(pos(:,1),pos(:,2),pos(:,3),1,[0 0 0],'filled');
    plot3(pos(:,1),pos(:,2),pos(:,3),'.k');
    hold on
    plot3(pos(biff_nodes,1),pos(biff_nodes,2),pos(biff_nodes,3),'og') % Starting flow node
    title('Bifurcations and endnodes');
    plot3(pos(end_nodes,1),pos(end_nodes,2),pos(end_nodes,3),'or') % Starting flow node
end

%%% Here, we show an example of a random trajectory selection in the
%%% directed graph using the shortestpathtree() function on 2 nodes
if display == 1
    disp('Directed graph visualisation...')
    start = 1;%randi([1 size(s,1)],1,1) % random integer from [1:#source_nodes]
    finish = start + randi([1 size(s,1)-start-1],1,1); % random integer from [start:#target_nodes-start]
    DG = digraph(s,t); % Directed graph generation
    [SP, D] = shortestpathtree(DG,start,finish); % Shortest path
    edges = table2array(SP.Edges); % Conversion
    nodes = edges(:,2)-1;
    trajectory = pos(nodes,:);
    %Plot 1 trajectory
    figure(4);clf;f = plot(SP); % Plot the shortest path graph variable
    f.XData = [pos(1,1);pos(:,1)];
    f.YData = [pos(1,2);pos(:,2)];
    f.ZData = [pos(1,3);pos(:,3)];
    f.EdgeColor = 'r';
    f.LineWidth = 3;
    f.ArrowSize = 10;
    hold on
    plot3(pos(biff_nodes,1),pos(biff_nodes,2),pos(biff_nodes,3),'og') % Starting flow node
    plot3(pos(end_nodes,1),pos(end_nodes,2),pos(end_nodes,3),'ok') % Starting flow node
    xlabel('x','FontSize',20);
    ylabel('y','FontSize',20);
    zlabel('z','FontSize',20);
    view(20,30)
    set(gcf,'color','w');
end

%% 1.4 Total network length calculation
%%% Parallel vectors between all nodes
parallel_vectors_between_nodes = pos(t(1:length(t)-1),:) -...
                                 pos(s(1:length(t)-1),:); 
%%% Euclidian norms calculation
 all_node_node_distances = sqrt(sum(diff(parallel_vectors_between_nodes,...
                                [],1).^2,2)); 
%%% Summing all norms to get total length
total_network_length = sum(all_node_node_distances);% um

%% 1.5 Calculating velocity-diameter and number of MB-diameter relationships
%%% In the article: Hingot, V., Errico, C., Heiles, B. et al.
%%% Microvascular flow dictates the comprimise between spatial resolution
%%% and acquisition time in Ultrasound Localisation Microscopy. Sci Rep 9,
%%% 2456 (2019). https://doi.org/10.1038/s41598-018-38349-x ,we use the
%%% equations related to Figure 4 C and D. 

log_d = linspace(0,5,1000); % Sampling diameter from 0 to 5 in log(mm)
log_N = 3.7*log_d -8.2;     % Number of MB log
d = exp(log_d);             % Diameter (mm)
N = exp(log_N);             % Number of MB
log_v = 1.9*log_d -6;       % Velocity log(mm/s)
v = exp(log_v);             % Velocity (mm/s)
d_sample_log = log(2*r);    % Diameters in our sample network log(mm)
v_sample_log = 1.9*(d_sample_log) -6;   % Velocities sample log(mm/s)
v_sample = exp(v_sample_log);           % Velocities sample (mm/s)
v_sample_um = v_sample*1000;            % Velocities sample (um)
d_sample = 2*r;             % Diameters in our sample network (mm)
N_sample_log = 3.7*d_sample_log -8.2;   % Number of MB log in our sample
N_sample = exp(N_sample_log);           % Number of MB in our sample
%%% Display
if display == 2 
    figure(6);clf
    subplot(2,3,1);plot(log_d,log_N,'LineWidth',2);
    hold on; plot(d_sample_log,N_sample_log,'.');
    grid on;title('Dependency of the bubble rate with vessel�s diameter');xlabel('log(d)');ylabel('log(N)');
    axis([0 5 0 8]);
    subplot(2,3,2);plot(d,N,'LineWidth',2);
    hold on; plot(d_sample,N_sample,'.');
    grid on;title('Dependency of the bubble rate with vessel�s diameter');xlabel('d (um)');ylabel('N');
    subplot(2,3,3);plot(d_sample,N_sample,'.');
    grid on;title('Sample dependency of the bubble rate with vessel�s diameter');xlabel('d (um)');ylabel('N');
    %%% v
    subplot(2,3,4);plot(log_d,log_v,'LineWidth',2);
    hold on; plot(d_sample_log,v_sample_log,'.');
    legend('Hingot','Sample data','Location','Best');
    grid on;title('Dependency of maximum velocity with vessel�s diameter');xlabel('log(d)');ylabel('log(v)');
    axis([0 5 -5 4]);
    subplot(2,3,5);plot(d,v,'LineWidth',2);
    hold on; plot(d_sample,v_sample,'.');
    legend('Hingot','Sample data','Location','Best');
    grid on;title('Dependency of maximum velocity with vessel�s diameter');xlabel('d (um)');ylabel('v (mm/s)');
    subplot(2,3,6);plot(d_sample,v_sample,'.');
    grid on;title('Dependency of maximum velocity with vessel�s diameter');xlabel('d (um)');ylabel('v (mm/s)');
    %figure;plot(d,v,'LineWidth',2);xlabel('d (um)');ylabel('v');title('Sample velocities');
    %axis([15 45 0 3.5]);
end

%% 1.6 Poiseuille distribution
x = linspace(-1,1,1000);
v_poiseuille = 1-x.^2;

%% 1.7 Pulsatility related parameters
%%% We emulate a pulsatile flow using a modified ECG. Using a specific
%%% heart frequency, we can multiply MB velocities with a normalized 
%%% factor as a function of time and vessel position later on.

% Velocity of the pulse. 
% https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3330793/
v_propagation_manual = 25000; %(um/s)
BPM = 300;          % Heartrate of 300 BPM to match a mouse heartrate
freq = BPM/60;      % Frequency (Hz)
period = 1/freq;    % Period (s)
dt = 1/samp_freq;   % Timestamp (s)
t_f = 1000;          % An arbitrary time length that overestimates necessary simulation time
% A condition to ensure that t_f is always larger or equal to desired 
% simulation time
if t_steady_state > t_f 
    t_f = t_steady_state;
end
x = 0:dt:t_f-dt;            % Time vector
ecg_raw = ecg(BPM,dt,t_f);  % ECG amplitude
ecg_filtered = ecg_raw-min(ecg_raw); % Translating vector above negative values
ecg_filtered2 = ecg_filtered./max(ecg_filtered); % Normalization
ecg_filtered3 = ecg_filtered2+0.5; % Translation so that mean = 1 and avoid close to 0 values
[ecg_filtered4,ylower] = envelope(ecg_filtered3,3,'peak'); % Take only the envelope to avoid abrupt changes
ecg_filtered4(ecg_filtered4>1.5) = 1.5;   % Ensure max value is 1.5
ecg_normalized = ecg_filtered4; % Just a step to leave room for subsequent filtering
if display == 2
    figure(7)
    clf
    plot(x ,ecg_normalized,'LineWidth',1.5);
    hold on 
    plot(x ,ecg_filtered4,'LineWidth',1.5);
    xlim([0 1])
    xlabel('Time (s)');
    ylabel('Multiplication Factor');
    title([num2str(BPM) ,' BPM']);
    % legend('ecg filtered','ecg filtered2','ecg filtered3','location','best');
    set(gca,'FontSize',14)
    grid on
end
clear ecg_filtered3 ecg_filtered2 ecg_filtered ecg_raw

%% 1.8 Trajectories statistics
%%% Here, we compute, for all possible trajectories, statistics such as the
%%% average vessel radius, minimal vessel radius, and so on to bo used in
%%% the next section. 
disp('Computing trajectories statistics... ~5-10 min');
DG = digraph(s,t,r_inverse); % Directed graph generation
end_nodes_biff = t;%s(2:end);% Merge endnodes and bifurcation nodes
%%% Initialization of variables
d_TRAJECTORIES = zeros(1,numel(end_nodes_biff));
mean_RADII = zeros(1,numel(end_nodes_biff));
median_RADII = zeros(1,numel(end_nodes_biff));
min_RADII = zeros(1,numel(end_nodes_biff));
max_RADII = zeros(1,numel(end_nodes_biff));
tic
%%% For all possible trajectories
for idx = 1:numel(end_nodes_biff)
    start = 1;  % Start at node #1
    [SP, ~] = shortestpathtree(DG,start,end_nodes_biff(idx)); % Shortest path
    edges = table2array(SP.Edges); % Get the nodes indexes
%     nodes = [edges(:,1);edges(end,2)]; % Add the last node from 2nd column
    nodes = edges(:,2)-1; % Nodes correspond to the previous indexes
    trajectory = pos(nodes,:); % Nodes positions attribution (x,y,z)
    d_TRAJECTORIES(idx) = sum(sqrt(sum(diff(trajectory,[],1).^2,2))); % Total length (um)
    mean_RADII(idx) = mean(r(nodes));       % Radii average in trajectory
    median_RADII(idx) = median(r(nodes));   % Radii median in trajectory
    min_RADII(idx) = min(r(nodes));         % Min radius in trajectory
    max_RADII(idx) = max(r(nodes));         % Max radius in trajectory
end
%%% We sort radii according to min, max, mean and median to obtain sorted
%%% indexes that can be used later on.
[mean_RADII_sorted,Idx_mean] = sort(mean_RADII,'descend');
[median_RADII_sorted,Idx_median] = sort(median_RADII,'descend');
[min_RADII_sorted,Idx_min] = sort(min_RADII,'descend');
[max_RADII_sorted,Idx_max] = sort(max_RADII,'descend');


if display == 2
    figure(8);clf
    plot(d_TRAJECTORIES,'.');title('Length');ylabel('Trajectory length (\mum)')
    figure(9);clf
    subplot(1,4,1);
    plot(mean_RADII_sorted,'.');title('Radius - Mean');ylabel('Mean trajectory radius (\mum)');
    subplot(1,4,2);
    plot(median_RADII_sorted,'.');title('Radius - Mean');ylabel('Mean trajectory radius (\mum)');
    subplot(1,4,3);
    plot(min_RADII_sorted,'.');title('Radius - MIN');ylabel('Min trajectory radius (\mum)');
    subplot(1,4,4);
    plot(max_RADII_sorted,'.');title('Radius - MAX');ylabel('Max trajectory radius (\mum)');
end
toc
beep2
%% 1.9 Trajectories selection probability
disp('Computing trajectories selection probability...');
min_length = 20; % Minimum bubble trajectory length (um) (empirically chosen)
% end_nodes_sorted = end_nodes(Idx_min);
end_nodes_biff_sorted = end_nodes_biff(Idx_min);
d_TRAJECTORIES_sorted = d_TRAJECTORIES(Idx_min);
%%% Remove too short trajectories
long_traject_idx = find(d_TRAJECTORIES_sorted>min_length);
end_nodes_biff_sorted = end_nodes_biff_sorted(long_traject_idx);
min_RADII_sorted_long = min_RADII_sorted(long_traject_idx);
%%%
radii = min_RADII_sorted_long; % Choosing min(radii) to avoid underestimating highly narrowing vessels
radii_rounded = round(min_RADII_sorted_long); % rounding
radii_unique = unique(radii_rounded); % Getting non-repeating vessel radii integers
% radii_unique_continuous = max(radii_unique):-1:min(radii_unique);
n_radii = numel(radii_unique);% number of differrent radii
%%% Using a relationship in the form of N = slope*diameter + intercept,
%%% where N is the MB count per diameter. Inspired from Hingot, V., Errico,
%%% C., Heiles, B. et al. Sci Rep 2019, figure 4 C.

slope = 3.7;
%%% The intercept will depend on the total number of MB we end up 
%%% simulating. The higher the number of simulated MBs, the higher the 
%%% intercept. We impose a linear relationship (intercept = 0) to 
%%% normalize the probabilites of the calculated trajectories.
intercept = 0;  

N_traject_log = slope*(log(radii*2))+intercept; % Number of MB log 

N_traject = exp(N_traject_log); % Number of MB

%%% Let's normalize the N so that sum(N) = 1
radii_count = histc(radii_rounded, radii_unique); % this will give the number of occurences of each unique element
radii_count = fliplr(radii_count); 
radii_unique = sort(radii_unique,'descend');
for i = 1:numel(radii_unique)
    start = sum(radii_count(1:i-1)) + 1;
    finish = sum(radii_count(1:i));
    N_traject_norm(start:finish) = N_traject(start:finish)/radii_count(i); % Divide probability by number of times that radius is repeated
end
N_traject_norm = N_traject_norm/sum(N_traject_norm); % normalize pdf

%% 2.1 MB trajectories simuation
%%% In section 2, we will compute all MB trajectories, one by one. To avoid
%%% filling the RAM which slows down the process, MB trajectories are 
%%% saved in small batches (paquets) locally, then gathered when all
%%% of them are saved. 
%%% As of now, all position of each trajectory are calculated one by one.
%%% A new MB position is calculated differently based on whether it is 
%%% before or after the forst graph node, and if the closest node is the
%%% next or previous one, hence the 4 IF statement. This can be optimized
%%% for faster computation.

disp('Starting simulation...');
fprintf('\n.......................');% Adding dots as spacers for fprintf at the end of the loop

padding_bubble = bubble_size/2; % To account for the fact that the bubbles are not infinitesimal points
tot_toc = 0; % For displaying progress to the user
min_poiseuille = 0.3; % Minimum Poiseuille value (a value of 0 causes an infinite computation time since the bubble doesn't move)
v_propagation = NaN;
std_hingot_velocity = 0;
debug_propagation_factor = 1; % Propagation slowdown factor
n_paquets = n_bubbles/bb_per_paquet;
%%% Random Sample from Discrete PDF
%%% https://www.mathworks.com/matlabcentral/fileexchange/37698-random-sample-from-discrete-pdf
%%% pdfrnd(x, p(x), sampleSize)
all_random_nodes = 1 + round(pdfrnd(0:numel(end_nodes_biff_sorted)-1, N_traject_norm, n_bubbles));

for pqt = 1:n_paquets % each paquet of trajectories
    clear bubbles_pqt % bubbles paquet
    bubbles_pqt = cell(bb_per_paquet,1);
    % Check for clicked Cancel button
    for trj = 1:bb_per_paquet % each trajectory
        tic
        bubbles_pqt{trj}.poiseuille_original = v_poiseuille(floor(length(v_poiseuille)*rand)+1); % random attribtution of a poiseuille coefficient
        bubbles_pqt{trj}.min_poiseuille_reached = 0;
        bubbles_pqt{trj}.dt = dt;
        if(bubbles_pqt{trj}.poiseuille_original < min_poiseuille) % if poiseuille ratio is lower than threshold
            bubbles_pqt{trj}.poiseuille = min_poiseuille; % Assign minimum value
            bubbles_pqt{trj}.min_poiseuille_reached = 1; % Assign flag
        else
            bubbles_pqt{trj}.poiseuille = bubbles_pqt{trj}.poiseuille_original;
        end
        clear X Y Z points new_distances dd distances_point_previous distances_next_previous closest_nodes delta pp ax bx cx dx ay by cy dy az bz cz dz  
        while 1 % create new trajectory while too short
            if bypass_N_vs_d_stats == 0 % Realistic
                %%% We generate the index of an end node for a trajectory
                %%% based on probability of occurence.
                random_end_node = all_random_nodes((pqt-1)*bb_per_paquet + trj);
            else % random, i.e. non realistic
                random_end_node = randi([1 length(end_nodes_biff_sorted)],1,1);
            end
            start = 1; % We start ad node #1
%             start = randi([1 size(s,1)],1,1) % random integer from [1:#source_nodes]
            [SP, ~] = shortestpathtree(DG,start,end_nodes_biff_sorted(random_end_node)); % Shortest path
            edges = table2array(SP.Edges);
            nodes = edges(:,2)-1; % It is the previous node!
            trajectory = pos(nodes,:); % Nodes positions attribution
            d_trajectory = sum(sqrt(sum(diff(trajectory,[],1).^2,2))); % Total length
            x = rand(1); % random distribution
            if and((d_trajectory > min_length),bubbles_pqt{trj}.poiseuille > x)
                break;
            end
        end

        vf_array = []; % Initialization
        ecg_array = []; % Initialization
        bubbles_pqt{trj}.d_trajectory = d_trajectory; % Trajectory length (um)
        distances = sqrt(sum(diff(trajectory,[],1).^2,2)); % Distances between each original node of the generated trajectory (um)
        distances_cum = cumsum(distances); % Cumulated distances (um)
        xyz = trajectory';
        spline_f = cscvn(xyz); % Creation of the cubic splines
        coefficients = spline_f.coefs; % Getting the coefficients
        start = 0; % (um) % Starting distance from first node
        %%% Vary the distance according to the closest node's radius
        dd = 0;
        new_distances(1,1) = start;
        k = 2;
        bubble_can_go_through = 1;
        while((d_trajectory-new_distances(k-1,1) > max(v_sample_um)*dt)&&bubble_can_go_through)
            previous_nodes_idx = find(distances_cum <= dd); % Finding the nodes that are before the point to get the closest but before node
            if(~isempty(previous_nodes_idx)) % if the starting distance is greater than the first node
                previous_node_idxes(k-1,1) = previous_nodes_idx(end)+1; % This is the previous node's index. 
                distances_point_previous(k-1,1) = dd - distances_cum(previous_node_idxes(k-1,1)-1); % Calculating the distance from previous node to know which of the next and previous are closest
                distances_next_previous(k-1,1) = distances_cum(previous_node_idxes(k-1,1)) - distances_cum(previous_node_idxes(k-1,1)-1);
                if((distances_point_previous(k-1)/distances_next_previous(k-1))<=0.5) % if previous point is closest
                    if(dd<d_trajectory) % if length not exceeding path length
                        closest_nodes(k-1,1) = previous_node_idxes(k-1,1);
                        if(pulsatility==1)
                            v = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            if k == 2 % Finding maximum velocity at begining of trajectory and set it as propagation velocity
                                v_propagation = v_propagation_manual;%v/debug_propagation_factor;
                            end
                            wave_delay = mod(floor((dd/v_propagation)*(period/dt)),period/dt);
                            wave_delays(k-1) = wave_delay;
                            wave_index = k+period/dt-wave_delay;%+(period/dt)-floor((dd/d_trajectory)*(period/dt));
                            wave_indexes(k-1) = wave_index;
                            vf = v*ecg_normalized(wave_index);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = ecg_normalized(wave_index); % Save ecg_normalized
                            dd = dd + dt*vf;
                        else
                            vf = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = 1; % Save ecg_normalized
                            dd = dd+dt*vf;
                        end
                        new_distances(k,1) = dd;%v_sample(closest_nodes(k-1));%dd + inter_distance*r_norm(closest_nodes(k-1)); % This is the important array which contains the distances between the new nodes
                        k = k+1;
                        if(r(nodes(closest_nodes(k-2))) - padding_bubble)<=0
                            bubble_can_go_through=0;
                        end
                    end
                else % if next node is closest
                    if(dd<d_trajectory) % if length not exceeding path length
                        closest_nodes(k-1,1) = previous_node_idxes(k-1,1)+1;
                        if(pulsatility==1)
                            v = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            if k == 2 % Finding maximum velocity at begining of trajectory and set it as propagation velocity
                                v_propagation = v_propagation_manual;%v/debug_propagation_factor;
                            end
                            wave_delay = mod(floor((dd/v_propagation)*(period/dt)),period/dt);
                            wave_delays(k-1) = wave_delay;
                            wave_index = k+period/dt-wave_delay;% + (period/dt)-floor((dd/d_trajectory)*(period/dt));
                            wave_indexes(k-1) = wave_index;
                            vf = v*ecg_normalized(wave_index);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = ecg_normalized(wave_index); % Save ecg_normalized
                            dd = dd + dt*vf;
                        else
                            vf = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = 1; % Save ecg_normalized
                            dd = dd + dt*vf;
                        end
                        new_distances(k,1) = dd;%dd + inter_distance*r_norm(closest_nodes(k-1));
                        k = k+1;
                        if(r(nodes(closest_nodes(k-2))) - padding_bubble)<=0
                            bubble_can_go_through=0;
                        end
                    end
                end
            else % the starting distance is less than the first node
                previous_node_idxes(k-1,1) = 1;
                next_node_idx = previous_node_idxes(k-1,1) + 1;
                distances_point_previous(k-1,1) = dd;
                distances_next_previous(k-1,1) = distances_cum(previous_node_idxes(k-1,1));
                if((distances_point_previous(k-1)/distances_next_previous(k-1))<=0.5) % if previous point is closest
                    if(dd<d_trajectory) % if length not exceeding path length
                        closest_nodes(k-1,1) = previous_node_idxes(k-1,1);
                        if(pulsatility==1)
                            v = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            if k == 2 % Finding maximum velocity at begining of trajectory and set it as propagation velocity
                                v_propagation = v_propagation_manual;%v/debug_propagation_factor;
                            end
                            wave_delay = mod(floor((dd/v_propagation)*(period/dt)),period/dt);
                            wave_index = k+period/dt-wave_delay;% + (period/dt)-floor((dd/d_trajectory)*(period/dt));
                            wave_delays(k-1) = wave_delay;
                            wave_indexes(k-1) = wave_index;
                            vf = v*ecg_normalized(wave_index);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = ecg_normalized(wave_index); % Save ecg_normalized
                            dd = dd + dt*vf;
                        else
                            
                            vf = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = 1; % Save ecg_normalized
                            dd = dd + dt*vf;
                        end
                        new_distances(k,1) = dd;%v_sample(closest_nodes(k-1));%dd + inter_distance*r_norm(closest_nodes(k-1));
                        k = k+1;
                    end
                else
                    if(dd<d_trajectory) % if length not exceeding path length
                        closest_nodes(k-1,1) = previous_node_idxes(k-1,1)+1;
                        if(pulsatility==1)
                            if k == 2 % Finding maximum velocity at begining of trajectory and set it as propagation velocity
                                v_propagation = v_propagation_manual;%v/debug_propagation_factor;
                            end
                            v = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            wave_delay = mod(floor((dd/v_propagation)*(period/dt)),period/dt);
                            wave_index = k+period/dt-wave_delay;%+ (period/dt)-floor((dd/d_trajectory)*(period/dt)); % The propagation wave
                            wave_delays(k-1) = wave_delay;
                            wave_indexes(k-1) = wave_index;
                            vf = v*ecg_normalized(wave_index);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = ecg_normalized(wave_index); % Save ecg_normalized
                            dd = dd + dt*vf;
                        else
                            vf = v_sample_um(nodes(closest_nodes(k-1)))*(bubbles_pqt{trj}.poiseuille);
                            vf_array(1,k-1) = vf; % save velocity
                            ecg_array(1,k-1) = 1; % Save ecg_normalized
                            dd = dd + dt*vf;
                        end
                        new_distances(k,1) = dd;%v_sample(closest_nodes(k-1));%dd + inter_distance*r_norm(closest_nodes(k-1));
                        k = k+1;
                    end
                end
            end
            dd = new_distances(k-1,1);
        end
        vf_array(1) = []; % removing first velocity (= 0)
        ecg_array(1) = []; % removing first velocity (= 0)
        bubbles_pqt{trj}.vf_array = vf_array; % saving velocity
        bubbles_pqt{trj}.ecg_array = ecg_array; % saving velocity
        bubbles_pqt{trj}.closest_nodes = nodes(closest_nodes); % Saving the closest nodes indexes
        %%%%% Calculation of the new positions using the cubic splines'
        %%%%% coefficients
        L = length(new_distances)-1;
        d = new_distances;
        delta = distances_point_previous./sqrt(distances_next_previous); % distance_point_previous_normalized with the square root. 
        % Delta is the scalar used to calculate the position of the new nodes using the distance and the cubic spline
        % Delta = (r/R)*sqrt(R) , where r : Distance from previous node, and R : local inter-node distance
        % point calculation using spline
        pp = (previous_node_idxes(1:L)-1)*3 +1; % Array created to get the good indices of oefficients
        ax = coefficients(pp,1);
        bx = coefficients(pp,2);
        cx = coefficients(pp,3);
        dx = coefficients(pp,4);
        X = ax.*(delta.^3) + bx.*(delta.^2) +...
            cx.*(delta) + dx; % X component
        ay = coefficients(pp+1,1);
        by = coefficients(pp+1,2);
        cy = coefficients(pp+1,3);
        dy = coefficients(pp+1,4);
        Y = ay.*(delta.^3) + by.*(delta.^2) +...
            cy.*(delta) + dy; % Y component
        az = coefficients(pp+2,1);
        bz = coefficients(pp+2,2);
        cz = coefficients(pp+2,3);
        dz = coefficients(pp+2,4);
        Z = az.*(delta.^3) + bz.*(delta.^2) +...
            cz.*(delta) + dz;  % Z component
        XYZ_centerLine = horzcat(X,Y,Z);
        %%% Laminar flow calculation
        clear xyz parallel perpendicular perpendicular2 radii
        %%% Computing vector parallel to the trajectory
        parallel = [XYZ_centerLine(2:end,1)-XYZ_centerLine(1:end-1,1) ...
                    XYZ_centerLine(2:end,2)-XYZ_centerLine(1:end-1,2) ...
                    XYZ_centerLine(2:end,3)-XYZ_centerLine(1:end-1,3)]; % vectors parallel to the nodes
        parallel_smooth = smooth(parallel,0.02); % Smoothing
        parallel_smooth = reshape(parallel_smooth,[size(parallel,1) 3]);
        parallel = parallel_smooth;
        perpendicular = zeros(size(parallel,1),3); % Initialization
        perpendicular2 = zeros(size(parallel,1),3); % Initialization
        for i = 1:size(parallel,1) % Probably a faster way to do this all at once
            perpendiculars = null(parallel(i,:)); % The null() function returns 2 orthogonal vectors to the set of 2 points
            perpendicular(i,:) = perpendiculars(:,1)'; %perpendicular vector 1
            perpendicular2(i,:) = perpendiculars(:,2)'; %perpendicular vector 2
        end
        %%% linear combination of the perpendicular vectors to extract a
        %%% random radial orientation. With a random radial orientation
        %%% vector, we can populate any oath in the vessel within the
        %%% theoretical boundaries of that vessel
        random_combination1 = rand(1);
        random_combination2 = rand(1);
        lin_combination = (-1+2*random_combination1)*perpendicular+...
                          (-1+2*random_combination2)*perpendicular2;
        %%% Normalize the lin_combination vector to obtain a circular
        %%% distribution rather than a rectangular one. This way, we get a
        %%% cylindrical flow instead of a rectangular one.
        lin_combination = lin_combination./norm(max(lin_combination));
        %%% Compensate for Poiseuille
        lin_combination = lin_combination.*(sqrt((1-bubbles_pqt{trj}.poiseuille_original))); % compensation of the radial component(lin_combination) by the poiseuille value
        bubbles_pqt{trj}.radii = abs(r(nodes(closest_nodes)) - padding_bubble); % Radii of the new nodes with compensation with half the bubble size
        laminar_xyz = XYZ_centerLine(1:end-1,:) + lin_combination.*bubbles_pqt{trj}.radii(1:end-1); % Vertices
        bubbles_pqt{trj}.XYZ_laminar = laminar_xyz; % Vertices
        bubbles_pqt{trj}.ID = (pqt-1)*bb_per_paquet + trj;

        [tot_toc, estimated_time_hours] = DisplayEstimatedTimeOfLoop(tot_toc+toc, bubbles_pqt{trj}.ID, n_bubbles); % Show progress to the user
        prog = ( 100*(bubbles_pqt{trj}.ID/n_bubbles) );
        fprintf(1,'\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b%3.0f%% | %s HH:MM:SS',prog,...
            datestr(estimated_time_hours, 'HH:MM:SS')); 
    end
    %% Save paquet of bubbles
    save([save_path 'temp\' 'bubbles_pqt_',file_name,'_paquet_',num2str(pqt),'_.mat'],'bubbles_pqt','-v7.3');
    clear bubbles_pqt
end
 fprintf('\n');
beep2

%% 2.2 Gather all Microbubbles
%%% In this section, we gather the temporarily saved MB trajectories and
%%% store them back in the RAM.
disp('Gathering paquets...')
clear bubbles
bubbles = cell(n_bubbles,1); % Initialization
for pqt = 1:n_paquets
    load([save_path 'temp\' 'bubbles_pqt_',file_name,'_paquet_',num2str(pqt),'_.mat'])
    for trj = 1:bb_per_paquet
        bubbles{trj+(pqt-1)*bb_per_paquet} = bubbles_pqt{trj};
    end
end
clear bubbles_pqt
delete([save_path 'temp\' 'bubbles_pqt_',file_name '*'])
%% Plot trajectories
n_bubbles_plot = 200;
if or(display==1,display==2)
    disp('Plotting Trajectories...');
    figure(10)
    clf
    scatter3(pos(:,1),pos(:,2),pos(:,3),1,[0 0 0],'filled') % Shortest path nodes);
    n_bubbles = size(bubbles,1);
    for jj = 1:n_bubbles_plot
        hold on
        plot1 = plot3(bubbles{jj}.XYZ_laminar(:,1),...
            bubbles{jj}.XYZ_laminar(:,2),...
            bubbles{jj}.XYZ_laminar(:,3),'LineWidth',2,...
            'Color', [(bubbles{jj}.poiseuille), 0, 1-bubbles{jj}.poiseuille]);
        plot1.Color(4) = 0.5;
%         drawnow
    end
    titre1 = 'Laminar flow simulation with';
    titre2 = num2str(n_bubbles);
    titre3 = ' trajectories.';
    titre_final = [titre1 titre2 ' ' titre3];
    title(titre_final);
    legend('Original nodes','Generated Laminar Flow - Red(fast) Blue(slow)','location','best');
    xlabel('x','FontSize',20);
    ylabel('y','FontSize',20);
    zlabel('z','FontSize',20);
    axis equal tight
    view(-22,-22)
end
drawnow

%% 2.3 Sorting Trajectories as a Function of Flow/Radius
disp('Sorting trajectories...');
clear flow_array
flow_array = [];
stats.RADII = [];
stats.mean_RADII = [];
radii_idx = 1;
for ii = 1:n_bubbles % Sorting as a function of r
    stats.RADII(radii_idx:radii_idx+numel(bubbles{ii}.radii)-1) = bubbles{ii}.radii;
    stats.mean_RADII(ii,1) = mean(bubbles{ii}.radii);
    radii_idx = radii_idx + numel(bubbles{ii}.radii);
end
[flow_array_sorted,flow_array_idx] = sort(stats.mean_RADII,1,'descend');

r_mean_sample = linspace(flow_array_sorted(1),flow_array_sorted(end),n_bubbles);
d_mean_sample_log = log(2*r_mean_sample);
N_mean_sample_log = 3.7*d_mean_sample_log;
N_mean_sample = exp(N_mean_sample_log);
rand_pdf = floor(randpdf(N_mean_sample,1:n_bubbles,[n_bubbles,1]))+1;
rand_pdf_times_N = rand_pdf.*r_mean_sample';
rand_pdf_times_N = floor(rand_pdf_times_N./max(rand_pdf_times_N)...
                    .*max(rand_pdf))+1; % Contains indexes of the bubbles 
rand_pdf_times_N(rand_pdf_times_N > n_bubbles) = n_bubbles; % Fix bound = n_bubbles
%                                      % to take in the SS calculation

%% 2.4 Computing statistics
disp('Computing statistics...');
stats.max_d = ceil(max(stats.mean_RADII*2));
stats.min_d = floor(min(stats.mean_RADII*2));
[stats.N_hist,stats.DIAMETER_hist] = hist(stats.mean_RADII*2,(stats.max_d-stats.min_d)/2);
stats.not_zeros_in_N = not(stats.N_hist==0);
stats.N_hist = stats.N_hist(stats.not_zeros_in_N);
stats.DIAMETER_hist = stats.DIAMETER_hist(stats.not_zeros_in_N);
if display == 2
    figure(11);clf;
    hist(stats.RADII*2,10);title('DIAMETERS');
    xlabel('d (\mum)');ylabel('N');
end
stats.x = log(stats.DIAMETER_hist');
stats.y = log(stats.N_hist');
stats.X = [ones(length(stats.x),1) stats.x];
stats.b = stats.X\stats.y;
stats.yCalc2 = stats.X*stats.b;
stats.yHingot = 3.7*stats.x-8.2;
if display == 2
    figure(12);clf;
    scatter(log(stats.DIAMETER_hist),log(stats.N_hist));hold on;plot(stats.x,stats.yCalc2,'--');
    plot(stats.x,stats.yHingot,'*-')
    xlabel('Log diameter');ylabel('Log N');
    if bypass_N_vs_d_stats == 0
        title('Log-Log N vs d')
    else
        title('Log-Log N vs d | Warning: N vs d constraint bypassed')
    end
    legend_title = ['y = ' num2str(stats.b(2)) 'x + ' num2str(stats.b(1))];
    legend('Count per diameter',legend_title,'Ref: y = 3.5x -8.5','Location','Best');

    figure(13);clf
    hist(rand_pdf_times_N,100);title('SS Flow Bubbles Probability');
    xlabel('Bubble ID');ylabel('N');
    figure(14);clf
    hist(rand_pdf,100);title('SS Flow Bubble Probability function');
    xlabel('Bubble ID');ylabel('N');
    figure(15);clf
    plot(r_mean_sample,N_mean_sample);
    xlabel('r  mean sample');ylabel('N mean sample');
    figure(16);clf
    subplot(1,2,1);
    n = ceil(max(r_mean_sample));
    hist(flow_array_sorted,n); xlabel('r');ylabel('');
    title('Hist flow array sorted');
    subplot(1,2,2);
    plot(flow_array_sorted)
end

%% 2.5 Save MB trajectories locally
disp('Saving bubbles...')
save_file_name = [file_name, '_', num2str(n_bubbles), '_bubbles_', ...
    num2str(n_bubbles_steady_state),'_bubbles_per_frame_', num2str(samp_freq),...
    '_Hz_', num2str(t_steady_state*1000), '_ms_'];
save([save_path 'bubbles_',save_file_name,'.mat'],'bubbles','samp_freq',...
    'n_bubbles','n_bubbles_steady_state','t_steady_state','bubble_size',...
    'pulsatility','slope','intercept','stats','v_propagation_manual',...
    'filename','-v7.3');

%% 3.1 Steady state flow calculation
disp('Starting steady state flow calculation...');
clear frames frames_velocities
dt = bubbles{1}.dt;
n_frames = t_steady_state/dt;
max_frames = 0;
bubble_count = 0;
loop_counter = 0;
k = 1;  % Bubble per frame counter (row in frames matrix)
ii = 1; % Frame number times 5
frm = 1; % frame number
tot_toc = 0;
frames_velocities = NaN(n_bubbles_steady_state,n_frames); % bubbles velocities
frames_ecg = NaN(n_bubbles_steady_state,n_frames); % bubbles ecg amplitude
frames_radii = zeros(n_bubbles_steady_state,n_frames);
frames_poiseuille = zeros(n_bubbles_steady_state,n_frames);
probability_fnct = (linspace(0,1,n_bubbles).^2);
% Simulation time verification
for jj = 1:length(bubbles)
    if size(bubbles{jj}.XYZ_laminar,1) > max_frames
        max_frames = size(bubbles{jj}.XYZ_laminar,1);
    end
end
if 0%n_frames > max_frames
    disp(['The maximum simulation time given the data is : ', num2str(max_frames*bubbles{1}.dt), ' s']);
else
    frames = NaN(n_bubbles_steady_state,n_frames);
    % Generate first set of bubbles
    pp = 1;
    while pp <= n_bubbles_steady_state
        frames(pp,ii) = rand_pdf_times_N(pp); % IDs
        random_index = randi([1 size(bubbles{frames(pp,ii)}.XYZ_laminar,1)],1,1);
        frames(pp,ii+1) = round(floor(random_index/(period/dt))*period/dt +1);    % idx
        if(size(bubbles{frames(pp,ii)}.XYZ_laminar,1)>=frames(pp,ii+1)) 
            frames(pp,ii+(2:4)) = bubbles{frames(pp,ii)}.XYZ_laminar(frames(pp,ii+1),:);
            frames_velocities(pp,1) = bubbles{frames(pp,ii)}.vf_array(frames(pp,ii+1));
            frames_ecg(pp,1) = bubbles{frames(pp,ii)}.ecg_array(frames(pp,ii+1));
            frames_radii(pp,1) = bubbles{frames(pp,ii)}.radii(frames(pp,ii+1));
            frames_poiseuille(pp,1) = bubbles{frames(pp,ii)}.poiseuille;
            pp = pp + 1;
        end
    end
    bubble_count = bubble_count + n_bubbles_steady_state;
    ii = ii + 5;
    frm = frm + 1;
    while frm <= n_frames
        tic
        loop_counter = loop_counter+1;
        while k <= n_bubbles_steady_state % Fill the column with bubbles IDs and time stamp index ii
            if(size(bubbles{frames(k,ii-5)}.XYZ_laminar,1) > frames(k,ii-4)) % The trajectory is not ended
                frames(k,ii) = frames(k,ii-5);
                frames(k,ii+1) = frames(k,ii-4)+1;
                frames(k,ii+(2:4)) = bubbles{frames(k,ii)}.XYZ_laminar(frames(k,ii+1),:);
                frames_velocities(k,frm) = bubbles{frames(k,ii)}.vf_array(frames(k,ii+1));
                frames_ecg(k,frm) = bubbles{frames(k,ii)}.ecg_array(frames(k,ii+1));
                frames_radii(k,frm) = bubbles{frames(k,ii)}.radii(frames(k,ii+1));
                frames_poiseuille(k,frm) = bubbles{frames(k,ii)}.poiseuille;
            else
                bubble_count = bubble_count + 1; % add new bubble
                frames(k,ii) = rand_pdf_times_N(bubble_count);
                if(pulsatility == 1)
                    sync_pos = mod(loop_counter,period/dt)+1;
                    if(sync_pos <= size(bubbles{frames(k,ii)}.XYZ_laminar,1)) % if synchronized position is possible
                        frames(k,ii+1) = sync_pos; % generate position synchronized with frame
                    else
                        frames(k,ii+1) = size(bubbles{frames(k,ii)}.XYZ_laminar,1); % generate position of new bubble at last position
                    end
                else
                    frames(k,ii+1) = randi([1 size(bubbles{frames(k,ii)}.XYZ_laminar,1)],1,1); % generate random position of new bubble
                end
                frames(k,ii+(2:4)) = bubbles{frames(k,ii)}.XYZ_laminar(frames(k,ii+1),:);
                frames_velocities(k,frm) = bubbles{frames(k,ii)}.vf_array(frames(k,ii+1));
                frames_ecg(k,frm) = bubbles{frames(k,ii)}.ecg_array(frames(k,ii+1));
                frames_radii(k,frm) = bubbles{frames(k,ii)}.radii(frames(k,ii+1));
                frames_poiseuille(k,frm) = bubbles{frames(k,ii)}.poiseuille;
            end
            k = k +1;
        end
        ii = ii + 5;
        frm = frm + 1;
        k = 1;
    tot_toc = DisplayEstimatedTimeOfLoop(tot_toc+toc, loop_counter, n_frames);
    end
    frames_label = ['Bubble ID | Bubble index | X(um) | Y(um) | Z(um)'];
    frames_param.dt = dt;
    frames_param.pulsatility = pulsatility;
    frames_param.t_f = t_f;
    frames_param.n_frames = n_frames;
    save([save_path 'frames_',save_file_name,'.mat'],'frames_label','frames',...
        'frames_velocities','samp_freq','n_bubbles','n_bubbles_steady_state',...
        't_steady_state','bubble_size','pulsatility','filename',...
        'stats','frames_radii','frames_poiseuille','frames_ecg','-v7.3');
end
beep2
disp('Successfully saved frames!')
fprintf('Theoretically, you could have simulated a maximum of  %3.1f s\n',...
    (n_bubbles/bubble_count*t_steady_state));

%% 4.1 Plot steady state flow
%%% Here we plot a constant MB concentration in time. 
if or(display==1,display==2)
    n_bubbles_steady_state = size(frames,1);
    figure(17);clf
    grid on
    n_frames = size(frames,2)/5;
    fast_forward = 8; % To speedup the visualization
    moving_average = 10;
    for jj = 11:fast_forward:n_frames-moving_average % Starting at 2 since initial velocities are 0
        view_idx = jj/30;
        pp = 3 + (jj-1)*5;
        c = jet(1001);
        scatter3(frames(:,pp),frames(:,pp+2),frames(:,pp+1),3,...
        c(ceil(1000*sqrt(((frames_velocities(:,jj)./...
        max(max(frames_velocities(:,jj-moving_average:jj+moving_average)))))))+1,:));
        axis equal
        xlim([min(pos(:,1)) max(pos(:,1))]); xlabel('x (\mum)');
        ylim([min(pos(:,3)) max(pos(:,3))]); zlabel('z (\mum)');
        zlim([min(pos(:,2)) max(pos(:,2))]); ylabel('y (\mum)');
        view(135,155);camorbit(180,180)
        set(gca,'GridAlpha',0.5);   
        title([num2str(round(jj/samp_freq,2)) ' s'])
        darkBackground(gcf)
        drawnow
    end
end
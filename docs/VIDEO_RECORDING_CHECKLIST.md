# Video Recording Checklist

Use this checklist to ensure a smooth video recording experience.

## Pre-Recording Setup

### Environment Preparation
- [ ] Run `./scripts/record-demo.sh` to verify everything is ready
- [ ] Clean terminal history: `history -c && clear`
- [ ] Increase terminal font size (18-20pt recommended)
- [ ] Use readable color scheme (Solarized Dark, Dracula, etc.)
- [ ] Set terminal size to 100 columns x 40 rows minimum
- [ ] Close unnecessary applications to reduce distractions
- [ ] Disable notifications (system and app notifications)

### Screen Recording Setup
- [ ] Screen resolution: 1920x1080 (Full HD) or higher
- [ ] Frame rate: 30 FPS minimum, 60 FPS preferred
- [ ] Audio: Test microphone, ensure quiet environment
- [ ] Cursor: Make visible and smooth (use Mouse Locator if needed)
- [ ] Recording area: Capture entire screen or specific region
- [ ] Test recording: Record 10 seconds and verify quality

### Content Preparation
- [ ] Review video script: `docs/VIDEO_DEMO_SCRIPT.md`
- [ ] Practice demo flow (at least once before recording)
- [ ] Prepare all commands in a separate file for easy copy-paste
- [ ] Have browser tabs ready (GitHub, Grafana, documentation)
- [ ] Prepare any diagrams or architecture drawings
- [ ] Test all commands beforehand to ensure they work

## Recording Steps

### Introduction (2 min)
- [ ] Clear introduction of topic
- [ ] Show repository/project overview
- [ ] Explain what viewers will learn
- [ ] Show project structure

### Architecture (3 min)
- [ ] Explain OpenTelemetry flow
- [ ] Show architecture diagram
- [ ] Explain local vs production deployment
- [ ] Explain chart separation rationale

### Setup (2 min)
- [ ] Check prerequisites (go, docker, kubectl, kind, helm)
- [ ] Show versions
- [ ] Verify everything is installed

### Local Testing Demo (5 min)
- [ ] Build application: `make build`
- [ ] Run tests: `make unit-tests`
- [ ] Deploy observability stack
- [ ] Check pods are ready
- [ ] Deploy application with dashboards
- [ ] Show ServiceMonitor and Dashboard ConfigMaps
- [ ] Generate traffic
- [ ] Verify telemetry export

### Production Demo (3 min)
- [ ] Show production values file
- [ ] Explain platform service references
- [ ] Show production deployment command
- [ ] Verify CRs reference platform services
- [ ] Explain differences from local testing

### Dashboard Walkthrough (3 min)
- [ ] Port-forward to Grafana
- [ ] Login to Grafana (admin/admin)
- [ ] Show Metrics Dashboard
  - [ ] HTTP Request Rate
  - [ ] Active Connections
  - [ ] Request Duration Percentiles
  - [ ] Response Size
  - [ ] Requests by Method/Status
  - [ ] Business Metrics
- [ ] Show Logs Dashboard
  - [ ] Application Logs Stream
  - [ ] Log Volume
  - [ ] Log Levels
  - [ ] Error Logs
- [ ] Show Traces Dashboard
  - [ ] Trace Search
  - [ ] Trace Rate
  - [ ] Trace Duration Distribution
  - [ ] Traces by Route
  - [ ] Traces by Status Code
- [ ] Click on a trace to show details

### Troubleshooting (1 min)
- [ ] Show common troubleshooting commands
- [ ] Explain common issues and solutions
- [ ] Provide tips and best practices

### Conclusion (1 min)
- [ ] Summarize key points
- [ ] Provide resources and links
- [ ] Call to action (like, subscribe)
- [ ] Thank viewers

## Post-Recording

### Editing
- [ ] Remove dead time (pauses, typos, loading)
- [ ] Add smooth transitions between sections
- [ ] Add text overlays for important points
- [ ] Add annotations/highlights for key commands
- [ ] Speed up long build/deployment processes (2x speed)
- [ ] Add chapter markers (for YouTube chapters)
- [ ] Add intro/outro graphics (optional)
- [ ] Verify audio quality throughout
- [ ] Check video quality and resolution

### YouTube Preparation
- [ ] Create engaging thumbnail
- [ ] Write detailed description with:
  - [ ] What viewers will learn
  - [ ] Timestamps/chapters
  - [ ] Prerequisites list
  - [ ] Key commands used
  - [ ] Links to resources
  - [ ] Relevant tags
- [ ] Add relevant tags (OpenTelemetry, Kubernetes, Grafana, etc.)
- [ ] Set video category (Education/Tutorial)
- [ ] Add end screen with subscribe button
- [ ] Add cards for related content (if available)
- [ ] Set video visibility (Unlisted first, then Public after review)

### Documentation Links
Include these in video description:
- [ ] GitHub repository URL
- [ ] Quick Start guide: [docs/OPENTELEMETRY_QUICK_START.md](OPENTELEMETRY_QUICK_START.md)
- [ ] Complete documentation: `docs/` folder
- [ ] E2E test guide: `docs/RUNNING_E2E_TESTS.md`
- [ ] Why separate charts: `docs/WHY_SEPARATE_OBSERVABILITY_STACK.md`

## Quick Command Reference for Video

```bash
# Build and test
make clean && make deps && make build
make unit-tests

# Deploy observability stack
./scripts/setup-observability-stack.sh

# Check deployment
kubectl get pods -n observability
kubectl get svc -n observability

# Deploy application
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace default \
  -f ./chart/dm-nkp-gitops-custom-app/values-local-testing.yaml

# Check app-specific CRs
kubectl get servicemonitor -n observability
kubectl get configmap -n observability -l grafana_dashboard=1

# Generate traffic
kubectl port-forward -n default svc/dm-nkp-gitops-custom-app 8080:8080 &
for i in {1..50}; do curl http://localhost:8080/; curl http://localhost:8080/health; curl http://localhost:8080/ready; sleep 0.2; done

# Access Grafana
kubectl port-forward -n observability svc/prometheus-grafana 3000:80
# http://localhost:3000 (admin/admin)

# Production deployment
helm install app ./chart/dm-nkp-gitops-custom-app \
  --namespace production \
  -f ./chart/dm-nkp-gitops-custom-app/values-production.yaml \
  --set grafana.dashboards.namespace=observability \
  --set monitoring.serviceMonitor.otelCollector.namespace=observability
```

## Pro Tips for Recording

1. **Practice First**: Record a practice run to identify issues
2. **Clear Terminal**: Start each section with `clear` command
3. **Pause for Loading**: Pause recording during long build/deploy processes
4. **Use Annotations**: Highlight important parts during editing
5. **Show Errors**: If something goes wrong, show how to troubleshoot
6. **Keep It Real**: Don't edit out all mistakes - they're relatable
7. **Good Lighting**: Ensure screen is clearly visible
8. **Consistent Speed**: Don't rush - speak clearly and slowly
9. **Engage Viewers**: Ask questions, use "you", make it interactive
10. **End Strong**: Clear conclusion with actionable next steps

## Troubleshooting During Recording

If something goes wrong during recording:
1. **Pause**: Stop recording, fix the issue
2. **Resume**: Continue from where you left off
3. **Edit**: Cut out the problem section during editing
4. **Explain**: If keeping the error, explain what went wrong and how to fix it

## Recording Tools Recommendations

### Screen Recording
- **macOS**: QuickTime Player (built-in), ScreenFlow, OBS Studio
- **Linux**: OBS Studio, SimpleScreenRecorder, Kazam
- **Windows**: OBS Studio, Camtasia, ScreenFlow

### Audio
- **Microphone**: USB microphone or good headset
- **Software**: Audacity for audio editing (if needed)

### Editing
- **macOS**: Final Cut Pro, iMovie, ScreenFlow
- **Linux**: OpenShot, Kdenlive, DaVinci Resolve
- **Windows**: Premiere Pro, DaVinci Resolve, Camtasia

### Terminal Enhancement
- **Terminal**: iTerm2 (macOS), Alacritty, Hyper
- **Font**: Fira Code, JetBrains Mono, Source Code Pro
- **Color Scheme**: Solarized Dark, Dracula, One Dark

## Final Checklist Before Publishing

- [ ] Video quality: 1080p or higher
- [ ] Audio quality: Clear and consistent
- [ ] All commands work and are visible
- [ ] All dashboards are shown working
- [ ] No sensitive information exposed
- [ ] Chapters/timestamps added
- [ ] Description complete with all links
- [ ] Tags are relevant and complete
- [ ] Thumbnail is eye-catching
- [ ] End screen with subscribe button
- [ ] Cards added (if applicable)
- [ ] Video is reviewed at least once
- [ ] Ready to publish!

---

**Good luck with your recording! 🎬📹**

const fs = require('fs').promises;

const JENKINS_URL = process.env.JENKINS_URL || 'https://cxone-ci.niceincontact.com/';
const USERNAME = process.env.JENKINS_USER || 'xxx';
const API_TOKEN = process.env.JENKINS_TOKEN || 'xxx';

const LOG_LEVELS = {
  INFO: 'INFO',
  WARN: 'WARN',
  ERROR: 'ERROR',
};

const formatLogMessage = (level, message) => {
  const timestamp = new Date().toISOString();
  return `[${timestamp}] [${level}] ${message}`;
};

const logInfo = (message) => console.log(formatLogMessage(LOG_LEVELS.INFO, message));
const logWarn = (message) => console.warn(formatLogMessage(LOG_LEVELS.WARN, message));
const logError = (message, error) => {
  const errorSuffix = error ? ` | ${error.message || error}` : '';
  console.error(formatLogMessage(LOG_LEVELS.ERROR, `${message}${errorSuffix}`));
};

const components = [
  'cloud-formation-applink-full-view-dashboard',
  'cloud-formation-applink-log-insights-queries',
  'cloud-formation-applink-performance-dashboard',
  'cloud-formation-hybrid-recording-alarms',
  'cloud-formation-hybrid-recording-amigos-dashboard',
  'cloud-formation-hybrid-recording-amigos-user-flow-dashboard',
  'cloud-formation-hybrid-recording-ec2',
  'cloud-formation-hybrid-recording-iam',
  'cxone-applink-audio-state-machine',
  'cxone-applink-screen-state-machine',
  'lambda-applink-billing-reporter',
  'lambda-applink-kinesis-consumer',
  'lambda-applink-leftover-ranges',
  'lambda-applink-metadata-rate-limiter',
  'lambda-applink-reconcile-segment-report',
  'lambda-applink-reconciliation-mailing-list',
  'lambda-applink-reprocessing-media',
  'lambda-applink-user-access-generator',
  'lambda-applink-users-rate-limiter-dlq',
  'lambda-hybrid-recording-audio-processing',
  'lambda-hybrid-recording-contact-id-producer',
  'lambda-hybrid-recording-contact-injector',
  'lambda-hybrid-recording-metadata-producer',
  'lambda-hybrid-recording-notify-users',
  'lambda-hybrid-recording-screen-processing',
  'lambda-hybrid-recording-user-cache',
  'lambda-hybrid-recording-user-sync',
  'lambda-hybrid-recording-user-sync-dlq',
  'lambda-hybrid-recording-user-token',
  'lambda-hybrid-recording-users-rate-limiter',
  'ms-hybrid-recording-storage-access-provider',
  'state-machine-applink-reconciliation-report',
  'cloud-formation-cxhist-alarms',
  'cloud-formation-cxhist-iam',
  'cloud-formation-cxhist-landing-area-dashboard',
  'cloud-formation-cxhist-media-upload-state-machine',
  'cloud-formation-cxhist-metadata-state-machine',
  'cloud-formation-cxhist-storage',
  'cloud-formation-rec-messaging',
  'cxone-cxhist-create-mapping-state-machine',
  'cxone-cxhist-status-report-state-machine',
  'lambda-cxhist-get-mapping-report',
  'lambda-cxhist-new-business-data',
  'lambda-cxhist-work-item-manger',
  'ms-cxhist-storage-access-provider',
  'state-machine-cxhist-billing-count',
  'state-machine-cxhist-ihub-evidence-report-collector',
  'state-machine-cxhist-rate-limiting',
  'state-machine-snf-TM-update-consumer',
  'cloud-formation-cxone-playvox-log-insights-queries',
  'cloud-formation-cxone-recording-snf-cloud-formation-snf-amc-poc',
  'cloud-formation-cxone-recording-snf-livevox-log-insights-queries',
  'cloud-formation-cxone-recording-snf-storage',
  'cloud-formation-cxone-recording-snf-ticketing-alarms',
  'cloud-formation-cxone-recording-snf-ticketing-dashboard',
  'lambda-cxone-recording-snf-agents-extractor',
  'lambda-cxone-recording-snf-amc-customer-connector',
  'lambda-cxone-recording-snf-amc-user-connect',
  'lambda-cxone-recording-snf-billing-writer',
  'lambda-cxone-recording-snf-getAttributeStore',
  'lambda-cxone-recording-snf-post-process',
  'lambda-cxone-recording-snf-saas-license-manager',
  'lambda-cxone-recording-snf-updateIntegrationSnapshot',
  'lambda-cxrec-snf-playvox-user-normalization',
  'lambda-cxrec-snfUserSyncErrorNotification',
  'lambda-cxrec-snfUsersErrorAggregation',
  'lambda-cxrec-snfUsersErrorGenerateReport',
  'state-machine-playvox-snf-tickets-metadata-normalization',
  'state-machine-snf-amc-media-processing',
  'state-machine-snf-billing-Reporter',
  'state-machine-snf-livevox-unzip-file',
  'state-machine-snf-media-uploader',
  'state-machine-snf-metadata-adapter',
  'state-machine-snf-metadata-enrichment',
  'state-machine-snf-tickets-orchestrator',
  'state-machine-snf-tickets-transcript-generator',
  'state-machine-snf-user-sync',
  'state-machine-ticket-metadata-enrichment'
];

const findJobPath = async (componentName) => {
  const searchUrl = `${JENKINS_URL}/search/suggest?query=${encodeURIComponent(componentName)}`;
  const auth = Buffer.from(`${USERNAME}:${API_TOKEN}`).toString('base64');

  try {
    const response = await fetch(searchUrl, {
      headers: {
        Authorization: `Basic ${auth}`,
      },
    });

    if (!response.ok) {
      logWarn(`Search request failed for "${componentName}" with status ${response.status}`);
      return null;
    }

    const searchResults = await response.json();

    if (!searchResults.suggestions || searchResults.suggestions.length === 0) {
      logWarn(`No suggestions returned for "${componentName}"`);
      return null;
    }

    for (const suggestion of searchResults.suggestions) {
      if (suggestion.name && suggestion.name.includes(componentName)) {
        const nameParts = suggestion.name.trim().split(/\s+/);
        const jobPath = nameParts.join('/job/');
        logInfo(`Found job path for "${componentName}": ${jobPath}`);
        return jobPath;
      }
    }

    logWarn(`No matching suggestion name found for "${componentName}"`);
    return null;
  } catch (error) {
    logError(`Error while searching job path for "${componentName}"`, error);
    return null;
  }
};

const getBuildNumber = async (jobPath) => {
  try {
    const consoleUrl = `${JENKINS_URL}job/${jobPath}/lastBuild/consoleText`;
    const auth = Buffer.from(`${USERNAME}:${API_TOKEN}`).toString('base64');
    
    const consoleResponse = await fetch(consoleUrl, {
      headers: {
        Authorization: `Basic ${auth}`,
      },
      redirect: 'follow',
    });

    if (!consoleResponse.ok) {
      logWarn(`Failed to fetch console log for job "${jobPath}" (status ${consoleResponse.status})`);
      return 'N/A';
    }

    const fullLog = await consoleResponse.text();

    const versionMatch = fullLog.match(/"displayName":"[^"]*version:\s*([^"]+)"/);
    if (versionMatch) {
      const version = versionMatch[1].trim();
      logInfo(`Extracted version "${version}" for job "${jobPath}" from displayName`);
      return version;
    }

    const buildMatch = fullLog.match(/Build\.Number[=:]?\s*(\d+\.\d+)/);
    if (buildMatch) {
      const buildNumber = buildMatch[1];
      logInfo(`Extracted build number "${buildNumber}" for job "${jobPath}" from Build.Number`);
      return buildNumber;
    }

    const revisionMatch = fullLog.match(/REVISION[=:]?\s*(\d+\.\d+)/);
    if (revisionMatch) {
      const revision = revisionMatch[1];
      logInfo(`Extracted revision "${revision}" for job "${jobPath}" from REVISION`);
      return revision;
    }

    logWarn(`No build number or version found in console log for job "${jobPath}"`);
    return 'N/A';
  } catch (error) {
    logError(`Error while getting build number for job "${jobPath}"`, error);
    return 'N/A';
  }
};

const run = async () => {
  const results = [];
  let lineNum = 1;

  logInfo(`Starting processing of ${components.length} components.\n`);

  for (const component of components) {
    logInfo(`${lineNum}/${components.length} Processing component: ${component}`);

    const jobPath = await findJobPath(component);

    if (!jobPath) {
      results.push(`${lineNum}. ${component} = N/A`);
      logWarn(`Build number for "${component}" is N/A (job path not found).\n`);
      lineNum++;
      continue;
    }

    const buildNumber = await getBuildNumber(jobPath);
    results.push(`${lineNum}. ${component} = ${buildNumber}`);
    logInfo(`Build number for "${component}": ${buildNumber}\n`);

    lineNum++;
  }

  const output = results.join('\n');
  await fs.writeFile('buildNumbersOld.txt', output, 'utf8');

  logInfo('=== Results saved to buildNumbersOld.txt ===');
  console.log(output);
};

run().catch(console.error);


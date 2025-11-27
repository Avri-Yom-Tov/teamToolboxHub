const fs = require('fs');

const JENKINS_URL = 'https://cxone-ci.niceincontact.com/';
const USERNAME = 'xxx';
const API_TOKEN = 'xxx';

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
  
  const response = await fetch(searchUrl, {
    headers: {
      'Authorization': `Basic ${auth}`
    }
  });
  
  if (!response.ok) {
    return null;
  }
  
  const searchResults = await response.json();
  
  if (!searchResults.suggestions || searchResults.suggestions.length === 0) {
    return null;
  }
  
  for (const suggestion of searchResults.suggestions) {
    if (suggestion.name && suggestion.name.includes(componentName)) {
      const nameParts = suggestion.name.trim().split(/\s+/);
      const jobPath = nameParts.join('/job/');
      return jobPath;
    }
  }
  
  return null;
};

const getBuildNumber = async (jobPath) => {
  try {
    const consoleUrl = `${JENKINS_URL}job/${jobPath}/lastBuild/consoleText`;
    const auth = Buffer.from(`${USERNAME}:${API_TOKEN}`).toString('base64');
    
    const consoleResponse = await fetch(consoleUrl, {
      headers: {
        'Authorization': `Basic ${auth}`
      },
      redirect: 'follow'
    });
    
    if (!consoleResponse.ok) {
      return 'N/A';
    }
    
    const fullLog = await consoleResponse.text();
    
    const versionMatch = fullLog.match(/"displayName":"[^"]*version:\s*([^"]+)"/);
    if (versionMatch) {
      return versionMatch[1].trim();
    }
    
    const buildMatch = fullLog.match(/Build\.Number[=:]?\s*(\d+\.\d+)/);
    if (buildMatch) {
      return buildMatch[1];
    }
    
    const revisionMatch = fullLog.match(/REVISION[=:]?\s*(\d+\.\d+)/);
    if (revisionMatch) {
      return revisionMatch[1];
    }
    
    return 'N/A';
  } catch (error) {
    return 'N/A';
  }
};

const run = async () => {
  const results = [];
  let lineNum = 1;
  
  console.log('Processing components...\n');
  
  for (const component of components) {
    console.log(`${lineNum}. Processing: ${component}`);
    
    const jobPath = await findJobPath(component);
    
    if (!jobPath) {
      results.push(`${lineNum}. ${component} = N/A`);
      console.log(`   Build number: N/A\n`);
      lineNum++;
      continue;
    }
    
    const buildNumber = await getBuildNumber(jobPath);
    results.push(`${lineNum}. ${component} = ${buildNumber}`);
    console.log(`   Build number: ${buildNumber}\n`);
    
    lineNum++;
  }
  
  const output = results.join('\n');
  fs.writeFileSync('buildNumbersOld.txt', output);
  
  console.log('\n=== Results saved to buildNumbers.txt ===');
  console.log(output);
};

run().catch(console.error);


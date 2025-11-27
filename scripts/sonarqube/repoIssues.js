const SONARQUBE_URL = 'https://sonar.nice.com';
const SONARQUBE_TOKEN = 'xxx';

const repositories = [
    'cloud-formation-applink-log-insights-queries'
];

const checkProjectIssues = async (projectKey) => {
    const fullProjectKey = `com.nice.${projectKey}`;
    const url = `${SONARQUBE_URL}/api/issues/search?componentKeys=${fullProjectKey}&resolved=false`;

    const headers = {
        'Authorization': `Bearer ${SONARQUBE_TOKEN}`
    };

    try {
        const res = await fetch(url, { headers });
        
        if (!res.ok) {
            if (res.status === 404) {
                return { projectKey, error: 'Project not found in SonarQube' };
            }
            return { projectKey, error: `HTTP ${res.status}` };
        }

        const data = await res.json();


        
        const issuesBySeverity = {
            BLOCKER: 0,
            CRITICAL: 0,
            MAJOR: 0,
            MINOR: 0,
            INFO: 0
        };

        data.issues.forEach(issue => {
            if (issuesBySeverity[issue.severity] !== undefined) {
                issuesBySeverity[issue.severity]++;
            }
        });

        return {
            projectKey,
            total: data.total || 0,
            issues: issuesBySeverity
        };
    } catch (error) {
        return { projectKey, error: error.message };
    }
};

const main = async () => {
    console.log(`Starting SonarQube check for ${repositories.length} repositories...\n`);
    console.log('='.repeat(80));

    const results = [];
    
    for (const repo of repositories) {
        console.log(`Checking: ${repo}...`);
        const result = await checkProjectIssues(repo);
        results.push(result);
    }

    console.log('\n' + '='.repeat(80));
    console.log('SUMMARY REPORT');
    console.log('='.repeat(80) + '\n');

    const withIssues = [];
    const withoutIssues = [];
    const errors = [];

    results.forEach(result => {
        if (result.error) {
            errors.push(result);
        } else if (result.total > 0) {
            withIssues.push(result);
        } else {
            withoutIssues.push(result);
        }
    });

    if (withIssues.length > 0) {
        console.log(`\n🔴 REPOSITORIES WITH ISSUES (${withIssues.length}):\n`);
        withIssues.sort((a, b) => b.total - a.total);
        
        withIssues.forEach(result => {
            console.log(`  📦 ${result.projectKey}`);
            console.log(`     Total: ${result.total} issues`);
            console.log(`     BLOCKER: ${result.issues.BLOCKER}, CRITICAL: ${result.issues.CRITICAL}, MAJOR: ${result.issues.MAJOR}, MINOR: ${result.issues.MINOR}, INFO: ${result.issues.INFO}`);
            console.log('');
        });
    }

    if (withoutIssues.length > 0) {
        console.log(`\n✅ REPOSITORIES WITHOUT ISSUES (${withoutIssues.length}):\n`);
        withoutIssues.forEach(result => {
            console.log(`  📦 ${result.projectKey}`);
        });
    }

    if (errors.length > 0) {
        console.log(`\n⚠️  ERRORS (${errors.length}):\n`);
        errors.forEach(result => {
            console.log(`  📦 ${result.projectKey}: ${result.error}`);
        });
    }

    console.log('\n' + '='.repeat(80));
    console.log(`Total Checked: ${repositories.length}`);
    console.log(`With Issues: ${withIssues.length}`);
    console.log(`Clean: ${withoutIssues.length}`);
    console.log(`Errors: ${errors.length}`);
    console.log('='.repeat(80));

    if (withIssues.length > 0) {
        console.log('\n📋 REPOSITORIES LIST WITH ISSUES (for copy-paste):\n');
        withIssues.forEach(result => {
            console.log(`nice-cxone/${result.projectKey}`);
        });
        console.log('');
    }
};

main().catch(err => console.error('Error:', err));


ms-cxhist-storage-access-provider
lambda-hybrid-recording-screen-processing
state-machine-snf-user-sync
state-machine-cxhist-cxhist-reprocess-media-upload
state-machine-snf-tickets-transcript-generator
lambda-cxrec-snf-playvox-user-normalization
state-machine-applink-reconciliation-report
state-machine-snf-media-uploader
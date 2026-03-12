console.log('Starting tenant search script...');​

const token = 'here';​
const environment = "dev";​
const searchForTenantId = "11eec997-c663-3860-895b-0242ac110005";​

const fetchAllTenants = async () => {
    const BASE_URL = `https://api-na1.${environment}.niceincontact.com/tenants/v2/current/subtenants/aggregatedInfo?withOwnershipProperties=true`;

    const headers = {
        accept: "application/json, text/plain, */*",
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "originating-service-identifier": "tm"
    };

    const allResults = [];
    let lastRecordId = null;
    const pageSize = 500;

    while (true) {
        const body = JSON.stringify({
            page: { pageSize, lastRecordId }
        });

        const res = await fetch(BASE_URL, {
            method: "POST",
            headers,
            body
        });

        if (!res.ok) {
            throw new Error(`Request failed: ${res.status}`);
        }

        const data = await res.json();
        console.log(`Fetched page data: ${JSON.stringify(data, null, 2)}`);

        const chunk = data.tenants ?? [];

        allResults.push(...chunk);

        console.log(`Retrieved ${chunk.length} tenants in this chunk`);

        if (chunk.length === 0) {
            break;
        }

        const newLastRecordId = data.page?.lastRecordId;

        console.log(`Next page lastRecordId: ${newLastRecordId}`);

        if (!newLastRecordId || newLastRecordId === lastRecordId) {
            break;
        }

        lastRecordId = newLastRecordId;
    }

    return allResults;
};

const searchTenant = async () => {
    try {
        const tenants = await fetchAllTenants();

        const tenantIds = tenants.map(({ tenantId }) => tenantId);
        console.log("Total tenants :", tenantIds.length);

        const foundTenant = tenants.find(({ tenantId }) => tenantId === searchForTenantId);
        
        if (foundTenant) {
            console.log(`\nTenant ${searchForTenantId} found !`);
            console.log("\nFull tenant data :");
            console.log(JSON.stringify(foundTenant, null, 2));
            return;
        }

        console.log(`\nTenant ${searchForTenantId} not found !`);
    } catch (err) {
        console.error(err);
    }
};

searchTenant();
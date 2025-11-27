







const token = 'here';
const environment = "dev";
const searchForTenantId = "11eec997-c663-3860-895b-0242ac110005";



const fetchAllTenants = async () => {

    const BASE_URL = `https://api-na1.${environment}.niceincontact.com/tenants/v2/current/subtenants/aggregatedInfo?withOwnershipProperties=true`;

    const headers = {
        "accept": "application/json, text/plain, */*",
        "authorization": `Bearer ${token}`,
        "content-type": "application/json",
        "originating-service-identifier": "tm"
    };

    let allResults = [];
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
        console.log(data);

        const chunk = data.tenants || [];

        allResults.push(...chunk);

        console.log(chunk.length);

        if (chunk.length === 0) {
            break;
        }

        const newLastRecordId = data.page?.lastRecordId;

        console.log(newLastRecordId);

        if (!newLastRecordId || newLastRecordId === lastRecordId) {
            break;
        }

        lastRecordId = newLastRecordId;
    }

    return allResults;
}







fetchAllTenants()

    .then(tenants => {

        const tenantIds = tenants.map(({ tenantId }) => tenantId);
        console.log("Total tenants :", tenantIds.length);


        const foundTenant = tenants.find(t => t.tenantId === searchForTenantId);
        if (foundTenant) {
            console.log(`\nTenant ${searchForTenantId} found !`);
            console.log("\nFull tenant data :");
            console.log(JSON.stringify(foundTenant, null, 2));
            return;
        }

        console.log(`\nTenant ${searchForTenantId} not found !`);
    })
    .catch(err => console.error(err));
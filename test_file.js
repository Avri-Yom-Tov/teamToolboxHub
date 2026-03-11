export const greet = (name) => {
  console.log(`Greeting user: ${name}`);
  return `Hello, ${name}!`;
};

export const farewell = (name) => {
  console.log(`Bidding farewell to user: ${name}`);
  return `Goodbye, ${name}!`;
};

export default greet;
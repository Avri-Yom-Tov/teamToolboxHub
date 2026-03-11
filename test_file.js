export const greet = (name) => {
  console.log(`[FUNCTION START] greet called`);
  console.log(`[INPUT] name type: ${typeof name}, value: ${name}`);
  console.log(`[VALIDATION] checking if name is valid...`);
  
  if (!name) {
    console.log(`[WARNING] name is empty or undefined, using default`);
    name = 'Guest';
  }
  
  console.log(`[PROCESSING] creating greeting message for: ${name}`);
  const message = `Hello, ${name}!`;
  console.log(`[OUTPUT] message created: ${message}`);
  console.log(`[OUTPUT] message length: ${message.length} characters`);
  console.log(`[FUNCTION END] greet completed successfully`);
  return message;
};

export const farewell = (name) => {
  console.log(`[FUNCTION START] farewell called`);
  console.log(`[INPUT] name type: ${typeof name}, value: ${name}`);
  console.log(`[VALIDATION] checking if name is valid...`);
  
  if (!name) {
    console.log(`[WARNING] name is empty or undefined, using default`);
    name = 'Guest';
  }
  
  console.log(`[PROCESSING] creating farewell message for: ${name}`);
  const message = `Goodbye, ${name}!`;
  console.log(`[OUTPUT] message created: ${message}`);
  console.log(`[OUTPUT] message length: ${message.length} characters`);
  console.log(`[FUNCTION END] farewell completed successfully`);
  return message;
};

export default greet;
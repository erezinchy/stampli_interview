# Use a slim version of Node
FROM node:20-alpine

# Create app directory
WORKDIR /usr/src/app

# Install dependencies first (better caching)
COPY package*.json ./
RUN npm install --production

# Copy app source
COPY . .

# Match the port in your Node code
EXPOSE 3000

# Start the application
CMD [ "node", "app.js" ]
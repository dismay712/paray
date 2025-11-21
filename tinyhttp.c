#include <stdio.h>      // Standard I/O functions (printf, perror)
#include <stdlib.h>     // Standard library functions (EXIT_FAILURE)
#include <string.h>     // String manipulation functions (strlen, strncpy)
#include <unistd.h>     // POSIX API (close, read, write)
#include <sys/types.h>  // Data types
#include <sys/socket.h> // Socket-related functions
#include <netinet/in.h> // Internet domain address structures (sockaddr_in)

// Define the port the server will listen on
#define PORT 8080
// Define the maximum number of pending connections
#define BACKLOG 10
// Define the size of the buffer to read incoming HTTP requests
#define BUFFER_SIZE 1024

/**
 * @brief Handles a single client connection.
 * * Reads the request, constructs a simple HTTP response, and sends it back.
 *
 * @param client_socket The file descriptor for the connected client socket.
 */
void handle_connection(int client_socket) {
    char buffer[BUFFER_SIZE] = {0};
    ssize_t bytes_read;

    // 1. Read the incoming HTTP request (up to BUFFER_SIZE)
    bytes_read = read(client_socket, buffer, BUFFER_SIZE - 1);
    if (bytes_read < 0) {
        perror("ERROR reading from socket");
        close(client_socket);
        return;
    }
    // Null-terminate the buffer for safe string handling
    buffer[bytes_read] = '\0';
    
    // Optional: Print the request line (for debugging)
    // char request_line[80];
    // strncpy(request_line, buffer, sizeof(request_line) - 1);
    // request_line[sizeof(request_line) - 1] = '\0';
    // printf("--- Received Request ---\n%s\n", request_line);


    // 2. Construct the HTTP Response
    // Status line and headers
    const char *status_line = "HTTP/1.1 200 OK\r\n";
    const char *header_content_type = "Content-Type: text/html\r\n";
    const char *header_connection = "Connection: close\r\n"; // Close the connection after response

    // HTML Body (simple "Hello, World!")
    const char *body = 
        "<!DOCTYPE html>"
        "<html><head><title>Tiny C Server</title></head>"
        "<body style='text-align:center; font-family:sans-serif;'>"
        "<h1>Hello from Alpine C Server!</h1>"
        "<p>This tiny server is running on port 8080.</p>"
        "</body></html>";

    // Calculate Content-Length
    size_t content_length = strlen(body);
    char header_content_length[64];
    snprintf(header_content_length, sizeof(header_content_length), "Content-Length: %zu\r\n", content_length);

    // Combine all parts into a final response
    char response[2048]; // Make sure this buffer is large enough for the full response
    int response_len = snprintf(response, sizeof(response),
                                "%s%s%s%s\r\n%s",
                                status_line,
                                header_content_type,
                                header_content_length,
                                header_connection,
                                body);

    // 3. Send the response back to the client
    if (write(client_socket, response, response_len) < 0) {
        perror("ERROR writing to socket");
    }

    // 4. Close the client connection
    close(client_socket);
}

/**
 * @brief Main function to set up and run the server.
 */
int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int addrlen = sizeof(address);
    int opt = 1; // Used for setsockopt to allow socket reuse

    // 1. Create socket file descriptor
    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    // Optional: Allows the socket to be reused immediately after closing
    // This prevents "Address already in use" error during rapid restarts
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt failed");
        exit(EXIT_FAILURE);
    }

    // Define the server address structure
    address.sin_family = AF_INET;           // IPv4
    address.sin_addr.s_addr = INADDR_ANY;   // Listen on all network interfaces
    address.sin_port = htons(PORT);         // Convert port number to network byte order

    // 2. Bind the socket to the specified port and address
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    // 3. Start listening for incoming connections
    if (listen(server_fd, BACKLOG) < 0) {
        perror("listen failed");
        exit(EXIT_FAILURE);
    }

    printf("Tiny C HTTP Server started on port %d...\n", PORT);
    printf("Access at: http://127.0.0.1:%d\n", PORT);

    // 4. Main server loop: Accept connections and handle them
    while (1) {
        // Accept blocks until a new connection arrives.
        // It returns a new file descriptor (new_socket) for the client connection.
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept failed");
            // Non-fatal error, continue listening
            continue; 
        }

        // Handle the accepted connection
        handle_connection(new_socket);

        // The new_socket is closed inside handle_connection()
    }

    // Close the listening socket (only reached if loop is broken)
    close(server_fd);
    return 0;
}

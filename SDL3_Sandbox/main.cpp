#include <SDL3/SDL.h>
#include <SDL3/SDL_init.h>
#include <SDL3/SDL_main.h>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <string_view>
using namespace std;

/* We will use this renderer to draw into this window every frame. */
static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;

/* This function runs once at startup. */
SDL_AppResult SDL_AppInit(void **appstate, int argc, char *argv[])
{
    SDL_SetAppMetadata("Beef IDE", "1.0", "com.beeflang.ide");

    if (!SDL_Init(SDL_INIT_VIDEO))
    {
        SDL_Log("Couldn't initialize SDL: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    if (!SDL_CreateWindowAndRenderer("Beef IDE", 640, 480, SDL_WINDOW_RESIZABLE | SDL_WINDOW_VULKAN, &window,
                                     &renderer))
    {
        SDL_Log("Couldn't create window/renderer: %s", SDL_GetError());
        return SDL_APP_FAILURE;
    }

    return SDL_APP_CONTINUE; /* carry on with the program! */
}

/* This function runs when a new event (mouse input, keypresses, etc) occurs. */
SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event)
{
    if (event->type == SDL_EVENT_QUIT)
    {
        return SDL_APP_SUCCESS; /* end the program, reporting success to the OS. */
    }
    return SDL_APP_CONTINUE; /* carry on with the program! */
}

/* This function runs once per frame, and is the heart of the program. */
SDL_AppResult SDL_AppIterate(void *appstate)
{
    const Uint64 now = SDL_GetTicks();

    /* we'll have the triangle grow and shrink over a few seconds. */
    const float direction = ((now % 2000) >= 1000) ? 1.0f : -1.0f;
    const float scale = ((float)(((int)(now % 1000)) - 500) / 500.0f) * direction;
    const float size = 200.0f + (200.0f * 1);

    SDL_Vertex vertices[4];
    int i;

    /* as you can see from this, rendering draws over whatever was drawn before it. */
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE); /* black, full alpha */
    SDL_RenderClear(renderer);                                   /* start with a blank canvas. */

    int w, h;
    SDL_GetWindowSize(window, &w, &h);

    /* Draw a single triangle with a different color at each vertex. Center this one and make it grow and shrink. */
    /* You always draw triangles with this, but you can string triangles together to form polygons. */
    SDL_zeroa(vertices);
    vertices[0].position.x = ((float)w) / 2.0f;
    vertices[0].position.y = (((float)h) - size) / 2.0f;
    vertices[0].color.r = 1.0f;
    vertices[0].color.a = 1.0f;
    vertices[1].position.x = (((float)w) + size) / 2.0f;
    vertices[1].position.y = (((float)h) + size) / 2.0f;
    vertices[1].color.g = 1.0f;
    vertices[1].color.a = 1.0f;
    vertices[2].position.x = (((float)w) - size) / 2.0f;
    vertices[2].position.y = (((float)h) + size) / 2.0f;
    vertices[2].color.b = 1.0f;
    vertices[2].color.a = 1.0f;

    SDL_RenderGeometry(renderer, NULL, vertices, 3, NULL, 0);
    /* put the newly-cleared rendering on the screen. */
    SDL_RenderPresent(renderer);

    return SDL_APP_CONTINUE; /* carry on with the program! */
}

/* This function runs once at shutdown. */
void SDL_AppQuit(void *appstate, SDL_AppResult result)
{
    /* SDL will clean up the window/renderer for us. */
}

int main(int argc, char *argv[])
{
    cout << "Hello World!" << endl;
    int res = SDL_EnterAppMainCallbacks(argc, argv, &SDL_AppInit, &SDL_AppIterate, &SDL_AppEvent, &SDL_AppQuit);
    return res;
}

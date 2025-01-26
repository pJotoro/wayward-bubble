#version 330 core
layout (location = 0) in vec4 vertex; // <vec2 position, vec2 texCoords>

out vec2 TexCoord;

uniform mat4 proj;

uniform vec2 pos;
uniform int frame_idx;
uniform int frame_count;

void main()
{
    TexCoord = vertex.zw;
    TexCoord.x += float(frame_idx)/frame_count;
    vec2 v = vertex.xy;
    v += pos;
    gl_Position = proj * vec4(v, 0.0, 1.0);
}